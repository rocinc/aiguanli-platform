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
  module Conversations
    class ActionContext < Context
      BODY_KEYS = %w[notes content comments text summary body description status_explanation subject title].freeze

      def visible_to?(user)
        record.on_behalf_of_id == user.id || record.decided_by_id == user.id ||
          (record.proposed? && record.decidable_by?(user))
      end

      def kind(user)
        return :draft if Assistant::Drafts.draft?(record, user)

        record.executed? || record.undone? ? :receipt : :proposal
      end

      def title(user)
        sentence = Assistant::Receipts::Sentence.new(record, user:).call if kind(user) == :receipt
        text = sentence ? sentence.text.sub(Assistant::Receipts::Sentence::MARK) { sentence.label.to_s } : record.title
        Assistant::Text.plain(text).squish.truncate(70)
      rescue StandardError
        record.title.to_s.truncate(70)
      end

      def chips(user)
        shape = kind(user)
        I18n.t("assistant.thread.chips.#{shape == :proposal ? :notice : shape}")
      end

      def body(user)
        [headline(user), about, steps, written(user), changes(user), people(user), basis, origin(user), failure].compact.join("\n")
      end

      def follow(conversation) = record.reload.updated_at > conversation.created_at

      def copies(user)
        drafts = Assistant::DraftComponent::DENSITIES.map do |density|
          [Assistant::DraftComponent.selector(record, density), Assistant::DraftComponent.new(action: record, user:, density:)]
        end
        receipts = Assistant::ReceiptComponent::DENSITIES.map do |density|
          [Assistant::ReceiptComponent.selector(record, density), Assistant::ReceiptComponent.new(action: record, user:, density:)]
        end
        (kind(user) == :receipt ? [] : drafts) + receipts
      end

      private

      def headline(user)
        say("action", kind: record.kind, title: line(record.title), status: record.status, tier: record.tier,
                      shape: say(kind(user).to_s))
      end

      def about = describe(record.subject)&.then { say("subject", text: it) }

      def steps
        lines = record.steps.first(6).map { "- #{step_line(it)}" }
        [say("steps"), *lines].join("\n") if lines.any?
      end

      def step_line(step)
        attrs = step["attributes"].to_h.except(*BODY_KEYS).map { |name, value| "#{name}=#{value}" }.join(", ")
        [step["op"], step["id"] && "##{step['id']}", attrs.presence].compact.join(" ")
      end

      def written(user)
        return unless kind(user) == :draft

        texts = record.steps.flat_map { |step| step["attributes"].to_h.slice(*BODY_KEYS).values }.compact_blank
        signer = if record.steps.any? { Assistant::Actions::Steps.for(it).in_deciders_name? }
                   say("signed_person")
                 else
                   say("signed_assistant", name: record.on_behalf_of&.name)
                 end
        targets = record.steps.filter_map { Assistant::Drafts::Target.for(it, user)&.label }
        [say("target", text: targets.to_sentence), signer, say("text", text: line_block(texts))].join("\n")
      end

      def line_block(texts) = Assistant::Text.plain(texts.join("\n\n")).truncate(900)

      def changes(user)
        preview = Assistant::PreviewPresenter.new(record.preview)
        consequences = Assistant::Consequences.new(preview, user:)
        lines = preview.direct_changes.first(6).map { "- #{line(consequences.line(it))}" }
        lines << "- #{say('cascade', count: preview.cascaded_changes.size)}" if preview.cascaded_changes.any?
        [say("changes"), *lines].join("\n") if lines.any?
      rescue StandardError
        nil
      end

      def people(user)
        names = (record.affected_users.to_a - [user]).map(&:name)
        say("people", text: names.to_sentence) if names.any?
      end

      def basis
        lines = record.basis_entries.first(5).map { "- #{line([it.label, it.quote.presence&.then { |quote| "\"#{quote}\"" }].compact.join(': '))}" }
        [say("basis"), *lines].join("\n") if lines.any?
      end

      def origin(user)
        signal = Assistant::Signal.offering(record).where(recipient: user).order(:id).last
        return unless signal

        say("origin", headline: line(signal.headline), detector: signal.detector,
                      certainty: say(signal.likely? ? "likely" : "certain"))
      end

      def failure = record.error.presence&.then { say("failure", text: line(it)) }
    end
  end
end
