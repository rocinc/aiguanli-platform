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
  module Desk
    class WatchingComponent < ApplicationComponent
      include OpPrimer::ComponentHelpers
      include Assistant::QuietWords

      Row = Data.define(:text, :url, :note)
      Promise = Data.define(:intent, :who, :hint, :title, :url, :ref, :date)

      DONE_WINDOW = 7.days
      VERSIONS_SHOWN = 5

      def initialize(project:, user:)
        super()
        @project = project
        @user = user
      end

      attr_reader :project, :user

      def watching
        @watching ||= [assigned_row, responsible_row, unclaimed_row, *version_rows, promised_row].compact
      end

      def promised_by_me = @promised_by_me ||= promises(said.mine, :mine)

      def asked_of_me = @asked_of_me ||= promises(said.requests_for_me, :asked)

      def promised_to_me = @promised_to_me ||= promises(said.owed_to_me, :owed)

      def questions_for_me = @questions_for_me ||= promises(said.questions_for_me, :question)

      def nothing_yet? = first_week? && watching.empty? && !agreements? && done.empty?

      def agreements? = agreement_groups.values.any?(&:any?)

      def agreement_groups
        { promised_by_me: promised_by_me, asked_of_me: asked_of_me, promised_to_me: promised_to_me,
          questions_for_me: questions_for_me }
      end

      def done
        @done ||= Assistant::Action.where(status: %w[executed undone], project:, on_behalf_of: user,
                                          executed_at: DONE_WINDOW.ago..)
                                   .includes(:on_behalf_of, :decided_by, :undone_by).order(executed_at: :desc).to_a
      end

      private

      def said = @said ||= Assistant::Said.new(user)

      def open_work_packages = WorkPackage.visible(user).with_status_open.where(project:)

      def assigned_row
        count = open_work_packages.where(assigned_to_id: user.id).count
        return if count.zero?

        Row.new(text: t("assistant.desk.watching.assigned", count:), url: list_path(assignedTo: [user.id]), note: nil)
      end

      def responsible_row
        count = open_work_packages.where(assigned_to_id: nil, responsible_id: user.id).count
        return if count.zero?

        Row.new(text: t("assistant.desk.watching.responsible", count:), url: nil, note: nil)
      end

      def unclaimed_row
        return unless lead?

        count = open_work_packages.where(assigned_to_id: nil, responsible_id: nil).count
        return if count.zero?

        Row.new(text: t("assistant.desk.watching.unclaimed", count:), url: nil, note: nil)
      end

      def version_rows
        return [] unless lead?

        project.versions.where(status: "open").order(:effective_date, :name).first(VERSIONS_SHOWN).map do |version|
          Row.new(text: t("assistant.desk.watching.version", name: version.name), url: helpers.version_path(version), note: nil)
        end
      end

      def promised_row
        return if promised_by_me.empty?

        Row.new(text: t("assistant.desk.watching.promised", count: promised_by_me.size), url: "#assistant-desk-promises",
                note: nil)
      end

      def lead? = leads.include?(user)

      def leads = @leads ||= Assistant::Proactive::Routing.leads(project)

      def list_path(**filters)
        props = { f: filters.map { |name, ids| { n: name.to_s, o: "=", v: ids.map(&:to_s) } } + [{ n: "status", o: "o", v: [] }] }
        helpers.project_work_packages_path(project, query_props: props.to_json)
      end

      def promises(scope, direction)
        scope.where(project:).filter_map { promise(it, direction) }
      end

      def promise(intent, direction)
        object = work_package_of(intent)
        return if object && (object.closed? || visible_ids.exclude?(object.id))

        name = other_person(intent, direction)
        Promise.new(intent:, who: who_text(direction, name), hint: load_hint(direction, name), title: intent.title,
                    url: object && helpers.work_package_path(object), ref: object && "##{object.id}",
                    date: date_text(intent, object))
      end

      def work_package_of(intent)
        intent.work_package || (intent.subject if intent.subject.is_a?(WorkPackage))
      end

      def visible_ids = @visible_ids ||= WorkPackage.visible(user).where(project:).pluck(:id).to_set

      def other_person(intent, direction)
        owner, counterparty = Assistant::IntentVerbs.speakers(intent, user)
        direction.in?(%i[owed question]) ? owner : counterparty
      end

      def who_text(direction, person)
        return t("assistant.desk.agreements.#{direction}_alone") unless person

        Assistant::PersonInText.call(self, "assistant.desk.agreements.#{direction}", { name: person })
      end

      def load_hint(direction, person)
        return unless direction == :owed && person

        render(Assistant::PersonLoadHintComponent.new(person:, always: false)).presence
      end

      def date_text(intent, object)
        [spoken_text(intent), promised_text(intent, object)].compact.join(" · ").presence
      end

      def spoken_text(intent)
        t("assistant.desk.agreements.spoken", day: Assistant::Text.day(intent.stated_at.to_date)) if intent.stated_at
      end

      def promised_text(intent, object)
        if intent.said_due_on
          promised_on(intent.said_due_on, open: object.present?)
        elsif object
          object.due_date ? t("assistant.desk.agreements.package_due", day: Assistant::Text.day(object.due_date)) : t("assistant.desk.agreements.no_date")
        end
      end

      def promised_on(date, open:)
        text = t("assistant.desk.agreements.said_then", day: Assistant::Text.day(date))
        days_late = (Time.zone.today - date).to_i
        return text unless open && days_late.positive?

        text + t("assistant.desk.agreements.overdue", days: days_late)
      end
    end
  end
end
