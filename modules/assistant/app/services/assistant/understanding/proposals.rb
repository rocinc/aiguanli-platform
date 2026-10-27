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
  module Understanding
    # Turns what a comment or a meeting asked to change (read by the extractor
    # in the same pass as promises and decisions) into actions on the real
    # work packages (06 S1). The change as said is previewed for the person
    # who said it; when that pushes a version late, the alternatives that keep
    # the date are prepared too (let someone with room take the next link, or
    # move what slips to the next version). A firm instruction from the
    # assignee or accountable that moves nothing else is done at once (T1);
    # everything else waits for the speaker as a card on the work package or
    # meeting and in their brief.
    class Proposals
      def self.for(source, raw_changes)
        said = SaidChanges.new(source, raw_changes)
        speaker = said.speaker
        return [] if speaker.nil? || raw_changes.blank?

        proposals = new(said, said.call)
        OpenProject::LocaleHelper.with_locale_for(speaker) { proposals.call }
      ensure
        Assistant::SourceSignalsComponent.broadcast_reload(source, proposals.touched) if proposals&.touched.present?
      end

      def initialize(said, changes)
        @said = said
        @changes = changes
        @touched = []
      end

      # Whose cards under the source changed: told so their page reloads them.
      attr_reader :touched

      def call
        @changes.group_by(&:work_package).filter_map { |wp, changes| propose(wp, fresh(changes)) }
      end

      private

      def speaker = @said.speaker

      def meeting? = source.is_a?(MeetingAgendaItem)

      # Said somewhere other than the work package's own comments.
      def elsewhere?(wp) = !meeting? && Assistant::Understanding::Sources.subject_of(source) != wp

      # A meeting's changes are the host's to confirm (06 S1). When the host
      # may not edit the work package, its accountable, then its assignee,
      # decides instead. Who presented the item is context, never authority.
      # Words written elsewhere (a forum post, a wiki edit) about a work
      # package follow the same rule: whoever wrote them decides if they may
      # edit it, otherwise the people answerable for it.
      def decider(wp)
        return speaker if speaker&.allowed_in_work_package?(:edit_work_packages, wp)
        return speaker unless meeting? || elsewhere?(wp)

        [wp.responsible, wp.assigned_to].find do
          it.is_a?(User) && it.active? && it.allowed_in_work_package?(:edit_work_packages, wp)
        end
      end

      def source = @said.source

      def project = @said.project

      def basis(changes) = [Assistant::Basis.for(source, quote: changes.map(&:quote).join(" / "))]

      def said_actions
        @said_actions ||= Assistant::Action.where(kind: "said_change", status: %w[proposed executed])
                                           .where("basis @> ?", [{ gid: source.to_gid.to_s }].to_json).to_a
      end

      # A change already proposed or done from this text is not proposed
      # again. When an edit gave a field a new value, the open proposal for
      # the old value gives way to one for the new.
      def fresh(changes)
        changes.reject do |change|
          fingerprint = change.fingerprint(source)
          earlier = said_actions.find { it.plan.dig("said", fingerprint) }
          next false if earlier.nil?
          next true if earlier.executed? || earlier.plan.dig("said", fingerprint) == change.attributes

          supersede!(earlier)
          false
        end
      end

      def supersede!(action)
        action.update!(status: "superseded")
        Assistant::Action.proposed.where(kind: "said_change_alternative", subject: action.subject)
                         .where("basis @> ?", [{ gid: source.to_gid.to_s }].to_json).update_all(status: "superseded")
        live = Assistant::Signal.live.where(action:)
        @touched.concat(User.where(id: live.select(:recipient_id)).to_a)
        live.update_all(state: "expired", outcome: "resolved", outcome_at: Time.current)
        said_actions.delete(action)
      end

      def propose(wp, changes)
        return if changes.empty?

        decider = @decider = decider(wp) or return
        return if Assistant::Signal.silenced?("said_change", recipient: decider, project:)

        steps = [{ "op" => "update_work_package", "type" => "WorkPackage", "id" => wp.id,
                   "attributes" => changes.map(&:attributes).reduce({}, :merge) }]
        primary = Assistant::Actions::Propose.call(
          kind: "said_change", title: changes.map(&:label).join("；"), steps:, on_behalf_of: decider, project:,
          subject: wp, basis: basis(changes), auto_execute: may_do_at_once?(wp, changes),
          said: changes.to_h { [it.fingerprint(source), it.attributes] }
        )
        return primary if primary.executed? || primary.status == "failed"

        options = [option(I18n.t("assistant.understanding.as_said"), consequence(primary), primary)]
        options.concat(alternatives(wp, steps, primary, changes))
        signal!(wp, primary, options, changes, decider)
        primary
      end

      # Done without asking only when it is written firmly by the person whose
      # work it is; Propose still holds it back unless the preview is T1.
      # Meeting notes do not say who spoke, so they always wait (a grant can
      # still lower the tier, explicitly).
      def may_do_at_once?(wp, changes)
        !meeting? && changes.all?(&:certain?) && speaker.id.in?([wp.assigned_to_id, wp.responsible_id].compact)
      end

      def alternatives(wp, steps, primary, changes)
        late = Array(primary.preview["version_slips"]).select { it["late"] && !it["was_late"] }
        return [] if late.empty?

        version = Version.find_by(id: late.first["version_id"]) or return []
        list = []
        last = last_link(wp, version)
        if last
          hours = Assistant::Facts.remaining_hours(last).nonzero? || 8.0
          helper, free = Assistant::Proactive::Routing.assignable(project)
                                                      .reject { [last.assigned_to_id, wp.assigned_to_id].include?(it.id) }
                                                      .map { [it, Assistant::Facts::Load.new(it, Date.current, last.due_date).free_hours] }
                                                      .select { _2 >= hours }.max_by(&:last)
          if helper
            parallel = { "assigned_to_id" => helper.id, "schedule_manually" => true,
                         "start_date" => last.start_date&.iso8601, "due_date" => last.due_date&.iso8601 }.compact
            action = alternative(wp, steps + [{ "op" => "update_work_package", "type" => "WorkPackage", "id" => last.id,
                                                "attributes" => parallel }],
                                 I18n.t("assistant.understanding.parallel", ref: "##{last.id}", name: helper.name), changes)
            if action
              list << option(action.title, [I18n.t("assistant.understanding.parallel_consequence", name: helper.name, free:),
                                            consequence(action, watching: version)].join("；"), action)
            end
          end
        end
        following = project.shared_versions.where(status: "open").where("effective_date > ?",
                                                                        version.effective_date).order(:effective_date).first
        if following
          slipping = slipping_items(wp, version)
          if slipping.any?
            action = alternative(wp, steps + slipping.map {
              { "op" => "update_work_package", "type" => "WorkPackage", "id" => it.id,
                "attributes" => { "version_id" => following.id } }
            },
                                 I18n.t("assistant.understanding.defer", list: slipping.map do
                                   "##{it.id}"
                                 end.join("、"), version: following.name), changes)
            list << option(action.title, consequence(action, watching: version), action) if action
          end
        end
        list
      end

      def alternative(wp, steps, title, changes)
        action = Assistant::Actions::Propose.call(kind: "said_change_alternative", title:, steps:, on_behalf_of: @decider,
                                                  project:, subject: wp, basis: basis(changes), auto_execute: false)
        action.status == "failed" ? nil : action
      end

      # The link that decides when the version finishes: done by someone else
      # on its current dates, it no longer waits for the moved work.
      def last_link(wp, version)
        graph = Assistant::Facts::ScheduleGraph.new(project)
        WorkPackage.where(id: graph.downstream(wp.id).to_a).with_target_version(version.id)
                   .where.not(status_id: Assistant::Facts.closed_status_ids).where.not(due_date: nil)
                   .order(due_date: :desc).first
      end

      def slipping_items(wp, version)
        graph = Assistant::Facts::ScheduleGraph.new(project)
        ids = [wp.id, *graph.downstream(wp.id)]
        WorkPackage.where(id: ids).with_target_version(version.id).where.not(status_id: Assistant::Facts.closed_status_ids)
                   .order(due_date: :desc).limit(3).to_a.reject { it.id == wp.id }
      end

      def option(label, consequence, action) = { "label" => label, "consequence" => consequence, "action_id" => action.id }

      def consequence(action, watching: nil)
        preview = action.preview || {}
        moved = Array(preview["cascaded"]).size
        slips = Array(preview["version_slips"])
        parts = []
        parts << I18n.t("assistant.understanding.moves", count: moved) if moved.positive?
        slips.each do |slip|
          finish = slip["finish_after"] && Assistant::Text.day(Date.iso8601(slip["finish_after"]))
          key = slip["late"] ? "slips" : "holds"
          parts << I18n.t("assistant.understanding.#{key}", version: slip["name"], finish:)
        end
        if watching && slips.none? { it["version_id"] == watching.id }
          parts << I18n.t("assistant.understanding.holds", version: watching.name,
                                                           finish: Assistant::Text.day(watching.effective_date))
        end
        people = User.where(id: Array(preview["affected_user_ids"])).map(&:name)
        parts << I18n.t("assistant.understanding.affects", names: people.join("、")) if people.any?
        parts.presence&.join("；") || I18n.t("assistant.understanding.nothing_else")
      end

      def signal!(wp, primary, options, changes, decider)
        subject = meeting? ? source.meeting : wp
        return unless decider
        %w[inline brief].each do |channel|
          Assistant::Signal.offer!(
            detector: "said_change", fingerprint: "#{source.to_gid}|#{primary.id}|#{channel}", recipient: decider,
            project:, subject:, action: primary, channel:, state: "pending", score: 30, deliver_at: Time.current,
            payload: { "headline" => I18n.t("assistant.understanding.headline", label: primary.title),
                       "because" => [*context_lines, *changes.map { "“#{it.quote}”" }],
                       "why_me" => why_me(decider, wp), "nature" => "decision",
                       "certainty" => changes.all?(&:certain?) ? "fact" : "likely", "options" => options, "source_gid" => source.to_gid.to_s, "work_package_id" => wp.id }
          )
          @touched << decider if channel == "inline"
        rescue ActiveRecord::RecordNotUnique
          nil
        end
      end

      def context_lines
        return [] unless meeting? && source.presenter.is_a?(User)

        [I18n.t("assistant.understanding.presented_by", name: source.presenter.name)]
      end

      def why_me(decider, wp)
        return I18n.t("assistant.understanding.why_elsewhere", name: speaker&.name) if elsewhere?(wp) && decider != speaker
        return I18n.t("assistant.understanding.why") unless meeting?
        return I18n.t("assistant.understanding.why_host") if decider == speaker

        I18n.t("assistant.understanding.why_instead_of_host", host: speaker.name)
      end
    end
  end
end
