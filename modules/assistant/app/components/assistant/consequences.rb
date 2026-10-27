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
  # The sentences that say what an action would do, shared by the card and by
  # the one-line consequence next to each option of a signal.
  class Consequences
    include Redmine::I18n

    def initialize(preview, user:)
      @presenter = preview.is_a?(PreviewPresenter) ? preview : PreviewPresenter.new(preview)
      @user = user
    end

    attr_reader :presenter, :user

    # One sentence per touched record. `label` is what stands for the object,
    # so that a surface can put a link there instead of the plain name.
    def line(change, label: change.label)
      scope = change.created ? "created" : "changed"
      key = line_key(change)
      key = "record" if key.blank? || !I18n.exists?("assistant.card.line.#{scope}.#{key}")
      I18n.t("assistant.card.line.#{scope}.#{key}", **facts(change, label))
    end

    def changes_text(change)
      change.attributes.map do |attribute|
        I18n.t("assistant.card.attribute_change", attribute: attribute_label(attribute.name, attribute.type),
                                                  before: value(attribute.before), after: value(attribute.after))
      end.join(I18n.t("assistant.card.separator"))
    end

    def slip(slip)
      key = if slip.newly_late then :slip_late
            elsif slip.recovered then :slip_recovered
            elsif slip.still_late then :slip_still_late
            else :slip_moves
            end
      I18n.t("assistant.card.#{key}", version: slip.name, before: value(slip.before), after: value(slip.after),
                                      target: value(slip.target))
    end

    def affected_names
      names = presenter.affected_users.map { it == user ? I18n.t("assistant.card.you") : it.name }
      names.to_sentence(two_words_connector: I18n.t("assistant.card.and"), words_connector: I18n.t("assistant.card.separator"),
                        last_word_connector: I18n.t("assistant.card.and"))
    end

    # One line: the main change, the cascade size, and a slip if it starts one.
    def summary
      return if presenter.empty?

      head = presenter.headline_change
      parts = [head && line(head)]
      parts << I18n.t("assistant.card.cascade", count: presenter.cascaded_changes.size) if presenter.cascaded_changes.any?
      parts.concat(presenter.newly_late_slips.map { slip(it) })
      parts.compact.join(I18n.t("assistant.card.sentence_separator"))
    end

    LABELLED = %w[WorkPackage Project Version WikiPage News Message TimeEntry Meeting].freeze

    def attribute_label(name, type = nil)
      return I18n.t("assistant.card.linked_work_packages") if name.to_s == "work_package_ids"

      model = LABELLED.include?(type.to_s) ? type.to_s.constantize : WorkPackage
      model.human_attribute_name(name.to_s.delete_suffix("_id"), default: name.to_s.humanize)
    end

    def line_key(change) = change.kind == "comment" && change.detail["internal"] ? "internal_comment" : change.kind

    def facts(change, label)
      detail = change.detail.symbolize_keys
      { label:, changes: changes_text(change), **detail, **spoken_facts(detail), **relation_facts(detail, label) }
    end

    def spoken_facts(detail)
      {
        from: day(detail[:from]), to: day(detail[:to]), on: day(detail[:on]), start: day(detail[:start]),
        at: detail[:at] && Assistant::Text.moment(Time.zone.parse(detail[:at])),
        frequency: detail[:frequency] && I18n.t("assistant.card.line.frequency.#{detail[:frequency]}", default: detail[:frequency])
      }.compact
    end

    def relation_facts(detail, label)
      return {} unless detail[:relation]

      { relation: I18n.t("assistant.card.line.relations.#{detail[:relation]}", from: label, to: detail[:target],
                                                                               default: "#{label} #{detail[:relation]} #{detail[:target]}") }
    end

    def day(iso) = iso.to_s.match?(/\A\d{4}-\d\d-\d\d\z/) ? Assistant::Text.day(Date.iso8601(iso)) : nil

    def value(value)
      case value
      when nil then I18n.t("assistant.card.empty_value")
      when Date then Assistant::Text.day(value)
      else value.to_s
      end
    end
  end
end
