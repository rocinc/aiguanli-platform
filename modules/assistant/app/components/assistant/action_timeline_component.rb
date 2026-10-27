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
  # How an action came to be and what became of it, oldest first: where it
  # came from, when it was proposed, who decided, the journals it wrote, and
  # whether it was taken back.
  class ActionTimelineComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    Entry = Data.define(:at, :icon, :text, :url)

    def initialize(action:, user:)
      super()
      @action = action
      @user = user
    end

    attr_reader :action, :user

    def entries
      list = [Entry.new(at: action.created_at, icon: :"light-bulb", text: proposed_text, url: nil)]
      list.concat(journal_entries)
      list << decision_entry if decision_entry
      list << Entry.new(at: action.undone_at, icon: :history, text: undone_text, url: nil) if action.undone_at
      list.sort_by(&:at)
    end

    private

    def proposed_text
      if action.on_behalf_of
        t("assistant.timeline.proposed_for", name: action.on_behalf_of.name, tier: t("assistant.actions.tiers.#{action.tier}"))
      else
        t("assistant.timeline.proposed", tier: t("assistant.actions.tiers.#{action.tier}"))
      end
    end

    def decision_entry
      @decision_entry ||=
        case action.status
        when "executed"
          text = if action.decided_by
                   t("assistant.timeline.executed_by",
                     name: action.decided_by.name)
                 else
                   t("assistant.timeline.executed_itself")
                 end
          Entry.new(at: action.executed_at || action.updated_at, icon: :"check-circle", text:, url: nil)
        when "rejected"
          name = action.decided_by&.name || t("assistant.timeline.someone")
          Entry.new(at: action.updated_at, icon: :skip, text: t("assistant.timeline.rejected_by", name:), url: nil)
        when "failed"
          Entry.new(at: action.updated_at, icon: :alert,
                    text: t("assistant.timeline.failed", error: action.error.to_s.truncate(200)), url: nil)
        end
    end

    def undone_text
      action.undone_by ? t("assistant.timeline.undone_by", name: action.undone_by.name) : t("assistant.timeline.undone")
    end

    def journal_entries
      Journal.where(id: Array(action.journal_ids)).includes(:journable).filter_map do |journal|
        journable = journal.journable
        next unless journable && visible?(journable)

        Entry.new(at: journal.created_at, icon: :pencil, text: t("assistant.timeline.journal", label: label(journable)),
                  url: url(journal, journable))
      end
    end

    def visible?(journable)
      journable.respond_to?(:visible?) ? journable.visible?(user) : true
    rescue ArgumentError
      journable.visible?
    end

    def label(journable)
      case journable
      when WorkPackage then "##{journable.id} #{journable.subject}"
      else journable.try(:name) || journable.try(:title) || journable.class.model_name.human
      end
    end

    def url(journal, journable)
      return unless journable.is_a?(WorkPackage)

      "#{helpers.work_package_path(journable)}/activity#activity-#{journal.version}"
    end
  end
end
