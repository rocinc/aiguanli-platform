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
  module Receipts
    # The sentence a receipt opens with: what was done, in the past tense, in
    # at most LIMIT characters. `text` holds MARK where the object is named,
    # so that the surface can put a link there.
    class Sentence
      MARK = "\u0000"
      LIMIT = 40
      SHORT_VALUE = 16
      NAMED_ATTRIBUTES = 3

      Result = Data.define(:text, :label, :url)

      def initialize(action, user:)
        @action = action
        @presenter = PreviewPresenter.new(action.preview)
        @consequences = Consequences.new(@presenter, user:)
      end

      def call
        head = presenter.headline_change
        return Result.new(text: action.title, label: nil, url: nil) unless head

        promise = promise_intent
        text = promise ? promised(head, promise) : (head.created ? created(head) : changed(head))
        text += I18n.t("assistant.receipt.more", count: presenter.direct_changes.size) if presenter.direct_changes.size > 1
        Result.new(text:, label: object_label(head), url: head.url || created_work_package_path(head))
      end

      private

      attr_reader :action, :presenter, :consequences

      def promise_intent
        return unless action.kind == "promise_date"

        gid = action.basis.filter_map { it["gid"] || it[:gid] }.first&.then { GlobalID.parse(it) }
        gid && Assistant::Intent.find_by(source_type: gid.model_name, source_id: gid.model_id, owner: action.on_behalf_of,
                                         subject_type: "WorkPackage", subject_id: action.subject_id)
      end

      def promised(change, intent)
        facts = { thing: MARK, ref: ref(change.label), who: intent.counterparty&.firstname, label: intent.title,
                  date: Assistant::Text.day(intent.said_due_on) }
        say(intent.counterparty ? "promised" : "promised_alone", facts)
      end

      def object_label(change)
        (created_work_package_ref(change) if change.created && change.kind == "work_package") || ref(change.label)
      end

      def created(change)
        facts = consequences.facts(change.with(detail: shorten_target(change.detail)), ref(change.label))
        facts = facts.merge(thing: MARK, ref: ref(change.label))
        key = change.kind
        key = "record" unless I18n.exists?("assistant.receipt.created.#{key}")
        if key == "work_package"
          key = "work_package_plain" unless created_work_package_path(change)
          facts = facts.merge(label: change.label, ref: created_work_package_ref(change).to_s)
        end
        key = "internal_comment" if key == "comment" && change.detail["internal"]
        key = "time_entry_own" if key == "time_entry" && change.detail["user"] == action.on_behalf_of&.name
        say("created.#{key}", facts)
      end

      def changed(change)
        facts = { thing: MARK, ref: ref(change.label), label: change.label }
        return say("changed.linked_pr", facts.merge(work_package: "##{linked_work_package_id}")) if linked_work_package_id && change.kind == "pull_request"

        return say("changed.wiki_page", facts) if change.kind == "wiki_page"

        attributes = asked(change)
        return say("changed.record", facts) if attributes.empty?

        names = attributes.map { consequences.attribute_label(it.name, it.type) }
        values = attributes.map { it.after.nil? ? nil : consequences.value(it.after) }
        return say("changed.cleared", facts.merge(attribute: names.first)) if attributes.one? && values.first.nil?

        if values.all? { it && it.length <= SHORT_VALUE }
          phrases = names.zip(values).map { |name, value| I18n.t("assistant.receipt.set", attribute: name, value:) }
          sentence = say("changed.values", facts.merge(attributes: phrases.join(I18n.t("assistant.receipt.separator"))))
          return sentence if visible(sentence, facts) <= LIMIT
        end

        say("changed.names", facts.merge(attributes: named(names)))
      end

      def linked_work_package_id
        action.steps.find { it["op"] == "link_pull_request" }&.dig("attributes", "work_package_id")
      end

      def asked(change)
        asked = action.steps.filter_map { it["attributes"].to_h.keys if "##{it['id']}" == ref(change.label) }.flatten
        change.attributes.select { asked.include?(it.name) }.presence || change.attributes
      end

      def named(names)
        names = names.uniq
        shown = names.first(NAMED_ATTRIBUTES - 1)
        return names.join(I18n.t("assistant.receipt.separator")) if names.size <= NAMED_ATTRIBUTES

        I18n.t("assistant.receipt.and_others", names: shown.join(I18n.t("assistant.receipt.separator")), count: names.size)
      end

      def say(key, facts)
        line = I18n.t("assistant.receipt.#{key}", **facts)
        over = visible(line, facts) - LIMIT
        return line unless over.positive?

        shrunk = facts.merge(%i[text label].index_with { facts[it] }.compact.transform_values { |value| shrink(value, over) })
        I18n.t("assistant.receipt.#{key}", **shrunk)
      end

      def shrink(value, over) = value.to_s.truncate([value.to_s.length - over, 6].max)

      def visible(line, facts) = line.sub(MARK, facts[:ref].to_s).length

      def ref(label) = label[/\A#\d+/] || label

      def shorten_target(detail) = detail["target"] ? detail.merge("target" => ref(detail["target"])) : detail

      def created_work_package_ref(change)
        found = action.inverse.find do |step|
          step["created"] && step["type"] == "WorkPackage" && step["label"].to_s.sub(/\A#\d+ /, "") == change.label.truncate(50)
        end
        found && "##{found['id']}"
      end

      def created_work_package_path(change)
        return unless change.created && change.kind == "work_package"

        id = created_work_package_ref(change)&.delete_prefix("#")
        OpenProject::StaticRouting::StaticUrlHelpers.new.work_package_path(id) if id
      end
    end
  end
end
