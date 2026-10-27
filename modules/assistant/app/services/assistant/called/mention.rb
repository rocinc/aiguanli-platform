# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  module Called
    # Someone wrote "@AI 助理 …": in a work package's comments, a forum post,
    # a news comment or a wiki edit note. The assistant reads it and its
    # thread, works it out with the same tools as the panel, and answers
    # there under its own name. Anything it
    # changes goes through propose for the person who asked: T1 is done and
    # said, T2/T3 is linked for them to confirm.
    class Mention
      PRIVATE_MARK = "[私下]"

      def initialize(record, llm: nil, asker: nil, placeholder: nil)
        @record = record
        @placeholder = placeholder
        @subject = Assistant::Understanding::Sources.subject_of(record)
        @project = Assistant::Understanding::Sources.project_of(record)
        @asker = asker || Assistant::Understanding::Sources.author_of(record)
        @llm = llm
      end

      def call
        return unless @asker.is_a?(User) && Assistant::Understanding::Sources.visible?(@record, @asker)
        return if answered?

        OpenProject::LocaleHelper.with_locale_for(@asker) { answer }
      end

      # The model cannot be reached: say so where the question was asked
      # instead of staying silent.
      def apologise(reason)
        return unless @asker.is_a?(User) && Assistant::Understanding::Sources.visible?(@record, @asker)

        OpenProject::LocaleHelper.with_locale_for(@asker) do
          sentence = I18n.t("assistant.called.mention.failed.#{reason}")
          step = reply_step("#{Assistant::Reasoning::StepBuilder.mention(@asker)} #{sentence}")
          step ? propose_reply(step, [Assistant::Basis.for(@record, quote: question.truncate(200))]) : tell_privately(sentence)
        end
      end

      private

      def answer
        conversation = Assistant::Conversation.create!(user: @asker, project: @project, context: @record,
                                                       origin: "mention", title: question.truncate(60))
        conversation.messages.create!(role: "user", content: question)
        result = begin
          User.execute_as(@asker) { agent(conversation).run(prompt) }
        rescue StandardError
          conversation.destroy
          raise
        end
        if result.content.blank?
          conversation.destroy
          raise Assistant::Llm::RetryableError, "empty answer"
        end

        public_text, private_text = split_private(result.content)
        conversation.messages.create!(role: "assistant", content: [public_text, private_text].compact_blank.join("\n\n"),
                                      cards: result.cards)
        post_reply(result, conversation, public_text, private_text)
      end

      def answered?
        asked = Assistant::Conversation.where(context: @record, origin: "mention")
        asked = asked.where(created_at: @record.updated_at..) if @record.is_a?(MeetingAgendaItem)
        asked.exists?
      end

      def question
        text = Assistant::Understanding::Sources.text_of(@record)
        return text unless @record.is_a?(MeetingAgendaItem)

        conclusions = @record.outcomes.reject(&:information_kind?).filter_map { Assistant::Text.plain(it.notes).presence }
        [text, *conclusions].join("\n")
      end

      def place = Assistant::Understanding::Sources.kind_of(@record)

      def agent(conversation)
        Assistant::Reasoning::Agent.new(user: @asker, project: @project, subject: @subject,
                                        conversation:, purpose: "mention", llm: @llm)
      end

      def prompt
        system = [Assistant::Reasoning::Constitution::TEXT,
                  Assistant::Reasoning::Situation.new(user: @asker, project: @project, subject: @subject).to_s,
                  I18n.t("assistant.called.mention.instructions", place: I18n.t("assistant.called.mention.places.#{place}"))]
                 .join("\n\n")
        [{ "role" => "system", "content" => system },
         { "role" => "user", "content" => "#{thread_text}\n\n#{I18n.t('assistant.called.mention.asked', name: @asker.name)}\n#{question}" }]
      end

      def thread_text
        turns = Assistant::Understanding::Sources.thread_of(@record)
        turns.reject! { |turn| turn.ref.start_with?("comment #") && internal_hidden?(turn.ref) }
        return "" if turns.empty?

        lines = turns.map { "[#{_1.at&.to_date&.iso8601}] #{_1.author&.name}: #{_1.text.truncate(500)}" }
        "#{I18n.t('assistant.called.mention.thread')}\n#{lines.join("\n")}"
      end

      def internal_hidden?(ref)
        journal = Journal.find_by(id: ref[/\d+/])
        journal&.internal? && !journal.visible?(@asker)
      end

      # The answer goes back where the question was asked, in the
      # assistant's own name. A wiki page has no thread, so there the answer
      # stays in the conversation the person is notified about.
      def post_reply(result, conversation, public_text, private_text)
        actions = Assistant::Action.where(id: action_ids(result.cards)).to_a
        spoken = [public_text.presence, (I18n.t("assistant.called.mention.privately") if private_text)].compact.join("\n\n")
        notes = ["#{Assistant::Reasoning::StepBuilder.mention(@asker)} #{spoken}", *actions.filter_map { action_line(_1) }].join("\n\n")
        step = reply_step(notes) or return notify_in_conversation(conversation)

        tell_privately_answer(private_text, conversation) if private_text
        propose_reply(step, [Assistant::Basis.for(@record, quote: question.truncate(200)), Assistant::Basis.for(conversation)])
      end

      # What the model marks as someone's own slip is not said in a thread
      # others read (S1.2); it goes to the person who asked.
      def split_private(content)
        head, tail = content.to_s.split(/^[ \t]*#{Regexp.escape(PRIVATE_MARK)}[ \t]*/, 2)
        [head.to_s.strip, tail.to_s.strip.presence]
      end

      def tell_privately_answer(text, conversation)
        Assistant::Signal.create!(
          detector: "mention_answer", fingerprint: "#{@record.to_gid}|private", recipient: @asker, project: @project,
          subject: @subject, channel: "inline", state: "pending", score: 40, deliver_at: Time.current,
          payload: { "headline" => text.lines.first.to_s.strip.truncate(120), "because" => ["“#{question.truncate(120)}”"],
                     "nature" => "answer", "options" => [open_conversation(conversation)] }
        )
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def replaced(klass)
        @placeholder.id if @placeholder.is_a?(klass)
      end

      def propose_reply(step, basis)
        Assistant::Actions::Propose.call(
          kind: "reply", title: I18n.t("assistant.called.mention.reply_title.#{place}", name: subject_name),
          steps: [step], on_behalf_of: @asker, project: @project, subject: @subject, basis:
        )
      end

      def tell_privately(sentence)
        if (signal = held_signal)
          return signal.update!(payload: signal.payload.except("holding").merge("headline" => sentence))
        end

        Assistant::Signal.create!(
          detector: "mention_answer", fingerprint: "#{@record.to_gid}|failed", recipient: @asker, project: @project,
          subject: @subject, channel: "inline", state: "pending", score: 40, deliver_at: Time.current,
          payload: { "headline" => sentence, "because" => ["“#{question.truncate(120)}”"], "nature" => "answer" }
        )
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def reply_step(notes)
        case @subject
        when WorkPackage
          { "op" => "comment", "type" => "WorkPackage", "id" => @subject.id, "replace" => replaced(Journal),
            "attributes" => { "notes" => notes, "internal" => Assistant::Understanding::Sources.internal?(@record) } }.compact
        when ::Message
          { "op" => "create_forum_reply", "replace" => replaced(::Message),
            "attributes" => { "message_id" => @subject.id, "content" => notes } }.compact
        when ::News
          { "op" => "create_news_comment", "attributes" => { "news_id" => @subject.id, "comments" => notes } }
        end
      end

      def notify_in_conversation(conversation)
        answer = conversation.messages.where(role: "assistant").order(:id).last&.content.to_s
        payload = { "headline" => answered_headline(answer), "because" => ["“#{question.truncate(120)}”"], "nature" => "answer",
                    "options" => [open_conversation(conversation)] }.merge(source_payload)
        payload["answer"] = answer if @record.is_a?(MeetingAgendaItem)
        signal = held_signal
        if signal
          signal.update!(payload:, state: "pending", deliver_at: Time.current)
        else
          signal = Assistant::Signal.create!(
            detector: "mention_answer", fingerprint: "#{@record.to_gid}|answer", recipient: @asker, project: @project,
            subject: @subject, channel: "inline", state: "pending", score: 40, deliver_at: Time.current, payload:
          )
        end
        Assistant::SourceSignalsComponent.broadcast_reload(@record, [@asker]) if @record.is_a?(MeetingAgendaItem)
        signal
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def held_signal
        Assistant::Signal.find_by(detector: "mention_answer", fingerprint: "#{@record.to_gid}|answer", recipient: @asker)
      end

      def source_payload = @record.is_a?(MeetingAgendaItem) ? { "source_gid" => @record.to_gid.to_s } : {}

      def answered_headline(answer)
        return I18n.t("assistant.called.mention.answered_in_conversation", name: subject_name) unless @record.is_a?(MeetingAgendaItem)

        answer.lines.first.to_s.strip.truncate(120)
      end

      def open_conversation(conversation)
        { "label" => I18n.t("assistant.signal.open_conversation"), "conversation_id" => conversation.id }
      end

      def subject_name
        case @subject
        when WorkPackage then "##{@subject.id}"
        when ::Message then @subject.subject
        else @subject.try(:title) || @subject.try(:name)
        end.to_s.truncate(60)
      end

      # Options laid out for a choice stay in the conversation; the thread only
      # lists the changes the assistant made or proposed itself.
      def action_ids(cards)
        cards.select { _1["type"] == "action" }.filter_map { _1["action_id"] }.uniq
      end

      def action_line(action)
        url = helpers.assistant_action_path(action)
        if action.executed?
          "- #{I18n.t('assistant.called.mention.done', title: action.title)} [#{I18n.t('assistant.called.mention.undo')}](#{url})"
        elsif action.proposed?
          "- #{I18n.t('assistant.called.mention.confirm', title: action.title)} [#{I18n.t('assistant.called.mention.open')}](#{url})"
        end
      end

      def helpers = OpenProject::StaticRouting::StaticUrlHelpers.new
    end
  end
end
