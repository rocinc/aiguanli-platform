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

module OpenProject::Assistant
  class Hooks < ::OpenProject::Hook::ViewListener
    # What this page shows, for the attention beacon (02 §1.1). A forum
    # thread counts as its first post; a wiki page only when it exists.
    VIEWED = { "@work_package" => "WorkPackage", "@meeting" => "Meeting", "@topic" => "Message", "@page" => "WikiPage",
               "@news" => "News", "@version" => "Version", "@project" => "Project" }.freeze

    def view_layouts_base_top_menu(context = {})
      mark_present(User.current)
      context[:hook_caller].render(::Assistant::TopMenuButtonComponent.new(user: User.current))
    end

    def view_layouts_base_body_bottom(context = {})
      controller = context[:controller] || context[:hook_caller].try(:controller)
      context[:hook_caller].render(::Assistant::PanelDialogComponent.new(user: User.current, context: page_object(controller),
                                                                         viewed: viewed_object(controller)))
    end

    def view_work_packages_activities_journal_bottom(context = {})
      journal = context[:journal]
      return "" if journal.nil? || journal.notes.blank?

      caller = context[:hook_caller]
      return asked_under(caller, journal) unless journal.user_id == User.current.id

      reading = ::Assistant::Reading.new(journal:, user: User.current)
      # While fresh, the reading line carries the proposals itself, since they
      # arrive after the comment was drawn.
      return proposals_under(caller, journal, journal.journable&.project).to_s if reading.state == :none

      caller.render(::Assistant::ReadingComponent.new(journal:, user: User.current, reading:))
    end

    def view_wiki_pages_form_comment_bottom(context = {}) = mention_hint(context)

    def view_time_entries_comments_form_bottom(context = {}) = mention_hint(context)

    def view_work_packages_date_picker_bottom(context = {})
      aside = ::Assistant::DateAside.for(context[:work_package], User.current)
      aside ? context[:hook_caller].render(::Assistant::DateAsideComponent.new(aside:)) : ""
    end

    def view_versions_form_effective_date_bottom(context = {})
      version = context[:version]
      return "" unless version&.persisted? && ::Assistant::Surface.available?(version.project, User.current)

      url = Rails.application.routes.url_helpers.assistant_version_date_aside_path(version)
      context[:hook_caller].render(::Assistant::DraftAsideComponent.new(frame_id: "assistant-version-aside-frame", url:,
                                                                        fields: { effective_date: "version[effective_date]" }))
    end

    def view_backlogs_index_top(context = {})
      context[:hook_caller].content_tag(:div, "", id: "assistant-backlogs-aside", class: "assistant-wp-aside-slot")
    end

    def controller_backlogs_work_package_moved(context = {})
      signal = ::Assistant::SprintMoveAside.for(work_package: context[:work_package], user: User.current)
      return "" unless signal

      view = context[:hook_caller].helpers
      notice = ::Assistant::NoticeComponent.new(signal:, user: User.current, density: :line, heading_level: 2)
      view.content_tag(:div, view.render(notice), class: "assistant-wp-aside")
    end

    def controller_projects_status_changed(context = {})
      ::Assistant::ProjectStatusAside.record(project: context[:project], user: User.current)
      ""
    end

    def view_projects_status_button_bottom(context = {})
      view = context[:hook_caller]
      signal = ::Assistant::ProjectStatusAside.fresh_for(project: context[:project], user: User.current)
      return view.content_tag(:div, "", id: "assistant-project-status-aside") unless signal

      notice = ::Assistant::NoticeComponent.new(signal:, user: User.current, density: :line, heading_level: 2)
      view.content_tag(:div, view.render(notice), id: "assistant-project-status-aside", class: "assistant-wp-aside")
    end

    def members_row_actions(context = {})
      member = context[:member]
      subject = member.principal
      return [] unless member.project_role? && subject.is_a?(::User) && !subject.is_a?(::AssistantUser) && subject.active?
      return [] unless ::Assistant::PerformanceAccess.new(context[:project], User.current).see?(subject)

      [{ scheme: :default, tag: :a, icon: :graph, label: I18n.t("assistant.performance.look"),
         href: Rails.application.routes.url_helpers.project_member_performance_path(context[:project], subject) }]
    end

    def view_members_index_top(context = {})
      project = context[:project]
      return "" unless ::Assistant::PerformanceAccess.new(project, User.current).view_others?

      caller = context[:hook_caller]
      caller.content_tag(:div, class: "mb-3") do
        caller.render(Primer::Beta::Link.new(href: Rails.application.routes.url_helpers.project_performance_team_path(project),
                                             data: { test_selector: "assistant-performance-team-link" })) do
          I18n.t("assistant.performance.team_link")
        end
      end
    end

    # One listener per meeting page for this person's proposals; it only
    # reloads the frames below, never carries the cards themselves.
    def view_meeting_agenda_top(context = {})
      meeting = context[:meeting]
      return "" if meeting.nil? || !::Assistant::Surface.available?(meeting.project, User.current)

      caller = context[:hook_caller]
      listener = caller.content_tag(
        :div, "", hidden: true, data: {
          controller: "assistant--live-frames", test_selector: "assistant-live-frames",
          "assistant--live-frames-signed-stream-value": ::Assistant::SourceSignalsComponent.signed_stream(meeting, User.current)
        }
      )
      caller.safe_join([listener,
                        caller.render(::Assistant::MeetingMinutesComponent.new(meeting:, user: User.current)),
                        caller.render(::Assistant::ObjectLineComponent.new(object: meeting, user: User.current)),
                        caller.render(::Assistant::MeetingRecapComponent.new(meeting:, user: User.current))])
    end

    # Always the frame, even empty, so proposals made later can be pushed in.
    def view_meeting_agenda_item_bottom(context = {})
      agenda_item = context[:agenda_item]
      meeting = agenda_item&.meeting
      return "" if meeting.nil? || !::Assistant::Surface.available?(meeting.project, User.current)

      context[:hook_caller].render(::Assistant::SourceSignalsComponent.new(source: agenda_item, user: User.current, frame: true))
    end

    def view_versions_show_top(context = {}) = marks_and_line(context, context[:version])

    def view_backlogs_sprint_report_top(context = {}) = object_line(context, context[:sprint])

    def view_wiki_show_top(context = {}) = marks_and_line(context, context[:page])

    def view_messages_show_top(context = {}) = object_line(context, context[:topic])

    def view_overviews_show_top(context = {}) = object_line(context, context[:project])

    def view_budgets_show_top(context = {}) = object_line(context, context[:budget])

    private

    def marks_and_line(context, object)
      return "" unless object&.persisted?

      caller = context[:hook_caller]
      caller.safe_join([caller.render(::Assistant::MarksComponent.new(object:, user: User.current)),
                        object_line(context, object)])
    end

    def object_line(context, object)
      return "" unless object&.persisted?

      context[:hook_caller].render(::Assistant::ObjectLineComponent.new(object:, user: User.current))
    end

    def mark_present(user)
      return unless user.logged?

      Rails.cache.fetch(["assistant/present", user.id, Date.current.iso8601], expires_in: 1.day) do
        ::Assistant::Away.mark_present!(user)
        true
      end
    end

    # The weighing of a request made in this comment, for the person asked: all of this person's notes under
    # comments come in one query for the page.
    def asked_under(caller, journal)
      signals = journal_notes(User.current)[journal.to_gid.to_s]
      return "" if signals.blank?

      notes = signals.map { |signal| ::Assistant::NoticeComponent.new(signal:, user: User.current, density: :line, heading_level: 4) }
      caller.content_tag(:div, caller.safe_join(notes.map { caller.render(it) }), class: "assistant-wp-aside")
    end

    def journal_notes(user)
      RequestStore.fetch([:assistant_journal_notes, user.id]) do
        next {} unless user.logged?

        ::Assistant::Signal.where(recipient: user, channel: "inline", detector: "request_weigh")
                           .where("payload ->> 'source_gid' LIKE 'gid://%/Journal/%'")
                           .where("outcome IS NULL OR outcome_at > ?", 1.day.ago).order(:created_at)
                           .group_by { it.payload["source_gid"] }
      end
    end

    def proposals_under(caller, source, project)
      return if source.nil? || !::Assistant::Surface.available?(project, User.current)

      signals = ::Assistant::SourceSignalsComponent.signals_for(source, User.current)
      caller.render(::Assistant::SourceSignalsComponent.new(source:, user: User.current, signals:)) if signals.any?
    end

    def viewed_object(controller)
      return if controller.nil? || !controller.request.get?

      VIEWED.each do |ivar, model|
        record = controller.instance_variable_get(ivar)
        record = record.__getobj__ if record.respond_to?(:__getobj__)
        return record if record.is_a?(model.constantize) && record.persisted?
      end
      nil
    end

    def page_object(controller)
      return if controller.nil?

      %i[@work_package @meeting @project].each do |ivar|
        record = controller.instance_variable_get(ivar)
        return record if record.is_a?(ActiveRecord::Base) && record.persisted?
      end
      nil
    end

    def mention_hint(context)
      return "" unless ::Assistant::Surface.available?(context[:project], User.current)

      context[:hook_caller].content_tag(:div, I18n.t("assistant.reach.mention_hint", login: ::AssistantUser::LOGIN),
                                        class: "FormControl-caption", data: { test_selector: "assistant-mention-hint" })
    end
  end
end
