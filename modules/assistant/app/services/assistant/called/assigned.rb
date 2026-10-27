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
    # A work package was handed to the assistant (01 §3.2). It says that it
    # is on it, reads the work package and everything around it, writes the
    # piece of work, attaches it, moves the work package to a review status
    # and hands it back to whoever assigned it. When it comes back with review
    # comments, it reads them and revises.
    class Assigned
      REVIEW_NAMES = %w[review 评审 待评审 审核 待验收 验收 测试中 resolved developed 开发完成].freeze
      DELIVERABLE_LIMIT = 12_000
      CANNOT = "CANNOT:"

      SYSTEM = <<~PROMPT
        You were assigned a work package as a member of the team. Do the work it asks for: a document,
        requirements, user stories, test cases, a research summary, a breakdown, acceptance criteria,
        release notes, a guide — whatever the work package is about. Use the tools to read the work
        package, its parent and children, related work, comments, decisions, meetings and wiki before you
        write. Use draft for the matching template. Ground claims in what you read and cite #ids.
        If this is a revision, the latest review comments say what to change: address every point.

        Mark every place in the deliverable that you could not settle with "◌" followed by what is open.
        If the work is not something you can do (it needs access, a decision or a person you do not have),
        answer only "CANNOT: " and one sentence saying what you cannot do and what is missing.

        Answer with exactly two parts separated by a line containing only "=====":
        1. a short note for the comment thread (2–4 sentences: what you read, what you produced, what the
           reviewer should look at first, anything you could not settle);
        2. the deliverable itself in Markdown, complete, in the language of the work package.
        Do not propose changes to work packages yourself; the deliverable is attached for review.
      PROMPT

      def initialize(journal, llm: nil)
        @journal = journal
        @work_package = journal.journable
        @assigner = journal.user
        @llm = llm
      end

      def call
        return unless @assigner.is_a?(User) && !@assigner.is_a?(AssistantUser)

        @progress = acknowledge!
        note, deliverable = produce
        said = (note.presence || deliverable).to_s
        return give_back_unfit!(said) if said.start_with?(CANNOT)

        hand_back!(note, deliverable)
      rescue Assistant::Llm::Error => e
        Rails.logger.error("[assistant] assigned ##{@work_package.id}: #{e.message}")
        give_back_unfinished!(e)
      end

      private

      def project = @work_package.project

      def revision? = Assistant::Conversation.exists?(context: @work_package, origin: "assigned")

      def conversation
        @conversation ||= Assistant::Conversation.create!(user: @assigner, project:, context: @work_package,
                                                          origin: "assigned", title: @work_package.subject.truncate(60))
      end

      def acknowledge!
        key = revision? ? "revising" : "started"
        comment!(I18n.t("assistant.called.assigned.#{key}", who: Assistant::Reasoning::StepBuilder.mention(@assigner)))
        @work_package.journals.reload.where(user: Assistant.user).order(:id).last
      end

      def produce
        request = I18n.t("assistant.called.assigned.task", id: @work_package.id, subject: @work_package.subject,
                                                           name: @assigner.name)
        conversation.messages.create!(role: "user", content: request)
        agent = Assistant::Reasoning::Agent.new(user: @assigner, project:, subject: @work_package, conversation:,
                                                purpose: "assigned", llm: @llm,
                                                tools: Assistant::Reasoning::Tools.read_only)
        system = [Assistant::Reasoning::Constitution::TEXT,
                  Assistant::Reasoning::Situation.new(user: @assigner, project:, subject: @work_package).to_s, SYSTEM].join("\n\n")
        result = User.execute_as(@assigner) do
          agent.run([{ "role" => "system", "content" => system }, { "role" => "user", "content" => "#{request}\n\n#{review_comments}" }])
        end
        conversation.messages.create!(role: "assistant", content: result.content)
        note, deliverable = result.content.split(/^\s*={5,}\s*$/, 2).map(&:strip)
        deliverable.present? ? [note, deliverable] : [nil, note]
      end

      def review_comments
        last_handback = @work_package.journals.where(user: Assistant.user).where.not(notes: [nil, ""]).reorder(:created_at).last
        scope = @work_package.journals.where.not(notes: [nil, ""]).where.not(user: Assistant.user)
        scope = scope.where(created_at: last_handback.created_at..) if last_handback && revision?
        comments = scope.reorder(:created_at).last(10)
        return "" if comments.empty?

        "#{I18n.t('assistant.called.assigned.comments')}\n" +
          comments.map { "- #{_1.user&.name}: #{Assistant::Text.plain(_1.notes).truncate(800)}" }.join("\n")
      end

      def hand_back!(note, deliverable)
        text = deliverable.to_s
        attachment = attach!(text) if text.length > DELIVERABLE_LIMIT
        attributes = { "assigned_to_id" => @assigner.id, "description" => described(text.first(DELIVERABLE_LIMIT)) }
        attributes["status_id"] = review_status.id if review_status
        body = [I18n.t("assistant.called.assigned.done", who: Assistant::Reasoning::StepBuilder.mention(@assigner)),
                note.presence, attachment && I18n.t("assistant.called.assigned.attached", name: attachment.filename)].compact.join("\n\n")
        Assistant::Actions::Propose.call(
          kind: "assigned_hand_back", title: I18n.t("assistant.called.assigned.title", id: @work_package.id),
          steps: [{ "op" => "comment", "type" => "WorkPackage", "id" => @work_package.id, "replace" => @progress&.id,
                    "attributes" => { "notes" => body } },
                  { "op" => "update_work_package", "type" => "WorkPackage", "id" => @work_package.id, "attributes" => attributes }],
          on_behalf_of: @assigner, project:, subject: @work_package,
          basis: [Assistant::Basis.for(@journal, label: I18n.t("assistant.called.assigned.basis", name: @assigner.name)),
                  Assistant::Basis.for(conversation)]
        )
      end

      # The draft goes under what was asked, so the request stays readable; a
      # revision replaces the earlier draft and leaves the request alone.
      def described(deliverable)
        heading = "## #{I18n.t('assistant.called.assigned.draft_heading')}"
        asked = @work_package.description.to_s.split(/\n*---\n+#{Regexp.escape(heading)}\b.*\z/m).first.to_s.strip
        [asked.presence, "---", "#{heading}\n\n#{deliverable}"].compact.join("\n\n")
      end

      def give_back_unfit!(note)
        reason = note.delete_prefix(CANNOT).strip
        replace_progress(I18n.t("assistant.called.assigned.cannot", who: Assistant::Reasoning::StepBuilder.mention(@assigner), reason:))
        User.execute_as(Assistant.user) do
          WorkPackages::UpdateService.new(user: Assistant.user, model: @work_package.reload).call(assigned_to_id: @assigner.id)
        end
        nil
      end

      def give_back_unfinished!(error)
        replace_progress(I18n.t("assistant.called.assigned.failed", who: Assistant::Reasoning::StepBuilder.mention(@assigner),
                                                                    reason: error.message.truncate(120)))
        User.execute_as(Assistant.user) do
          WorkPackages::UpdateService.new(user: Assistant.user, model: @work_package.reload).call(assigned_to_id: @assigner.id)
        end
      end

      def replace_progress(text)
        return comment!(text) unless @progress

        User.execute_as(Assistant.user) { Journals::UpdateService.new(model: @progress, user: Assistant.user).call(notes: text) }
      end

      def comment!(text)
        User.execute_as(Assistant.user) do
          AddWorkPackageNoteService.new(user: Assistant.user, work_package: @work_package).call(text)
        end
      end

      def attach!(text)
        return nil if text.blank?

        filename = "#{@work_package.subject.parameterize.presence || "work-package-#{@work_package.id}"}-#{Date.current.iso8601}.md"
        Tempfile.create(["assistant", ".md"]) do |file|
          file.write(text)
          file.flush
          file.rewind
          call = User.execute_as(Assistant.user) do
            Attachments::CreateService.bypass_allowlist(user: Assistant.user)
                                      .call(container: @work_package, file:, filename:, description: I18n.t("assistant.called.assigned.attachment"))
          end
          call.success? ? call.result : nil
        end
      end

      def review_status
        @review_status ||= begin
          contract = WorkPackages::UpdateContract.new(@work_package.reload, @assigner)
          allowed = contract.assignable_statuses.to_a - [@work_package.status]
          REVIEW_NAMES.lazy.filter_map { |name| allowed.find { _1.name.downcase.include?(name) } }.first
        end
      end
    end
  end
end
