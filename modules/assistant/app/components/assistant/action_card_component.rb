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
  # The one way an action is drawn: what it is, why, what it would do to
  # whom, and the buttons the viewer may press right now. Every surface
  # (panel, signals, brief, the provenance page) renders this, and every
  # button answers with a Turbo Stream that redraws all copies on the page.
  class ActionCardComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    VARIANTS = %i[full compact].freeze

    # `siblings` are the other actions offered as alternatives to this one;
    # choosing one declines the rest. `conflicts` come back from an undo that
    # would overwrite later edits.
    def initialize(action:, user:, variant: :full, siblings: [], conflicts: nil, heading_level: 3, notice: nil, undo_preview: nil)
      super()
      @action = action
      @user = user
      @variant = VARIANTS.include?(variant&.to_sym) ? variant.to_sym : :full
      @siblings = Array(siblings).map(&:to_i) - [action.id]
      @conflicts = conflicts
      @heading_level = heading_level.to_i.clamp(2, 6)
      @notice = notice
      @undo_preview = undo_preview
    end

    attr_reader :action, :user, :variant, :siblings, :conflicts, :notice, :undo_preview

    def self.selector(action, variant) = "[data-assistant-action-id='#{action.id}'][data-assistant-variant='#{variant}']"

    def id = "assistant-action-#{action.id}-#{variant}"

    def title_id = "#{id}-title"

    def compact? = variant == :compact

    def heading_tag = :"h#{@heading_level}"

    def preview = @preview ||= PreviewPresenter.new(action.preview)

    delegate :status, to: :action

    def css_classes
      ["assistant-card", "assistant-card--#{variant}", "assistant-card--#{status}",
       ("assistant-card--late" if preview.newly_late_slips.any? && action.proposed?)]
    end

    def tier_label = t("assistant.actions.tiers.#{action.tier}")

    def status_label = t("assistant.actions.statuses.#{status}")

    def status_icon
      { "proposed" => :question, "executed" => :"check-circle", "rejected" => :skip,
        "undone" => :history, "failed" => :alert, "superseded" => :history }.fetch(status, :dot)
    end

    def status_scheme
      { "proposed" => :accent, "executed" => :success, "rejected" => :secondary,
        "undone" => :secondary, "failed" => :danger, "superseded" => :secondary }.fetch(status, :secondary)
    end

    delegate :on_behalf_of, to: :action

    def actor_line
      return t("assistant.card.by_itself") if on_behalf_of.nil?
      return t("assistant.card.for_you") if on_behalf_of == user

      t("assistant.card.for_someone", name: on_behalf_of.name)
    end

    def timestamp = action.executed_at || action.undone_at || action.updated_at

    def basis = @basis ||= action.basis_entries

    def basis_url(entry) = Assistant::Provenance.url_for_basis(entry.to_h)

    # What the assistant would say in public, word for word, and where: a
    # person confirms the words, not only that "a comment is created".
    SPOKEN = { "comment" => "notes", "create_forum_reply" => "content", "create_news_comment" => "comments",
               "create_wiki_page" => "text", "update_project_status" => "status_explanation",
               "create_work_package" => "description", "update_work_package" => "description",
               "publish_news" => "description", "send_mail" => "body" }.freeze

    def spoken
      @spoken ||= action.steps.filter_map do |step|
        text = step.dig("attributes", SPOKEN[step["op"].to_s]).presence or next

        text = text.to_s
        wiki_change(step, text) || description_change(step, text) || { op: step["op"].to_s, text: plain(text) }
      end
    end

    # A page that already exists is changed, not written: what is added at
    # the end is what to read, and whose page it is says why it waits.
    def wiki_change(step, text)
      return unless step["op"] == "create_wiki_page"

      page = Project.find_by(id: step.dig("attributes", "project_id"))&.wiki&.find_page(step.dig("attributes", "title"))
      return unless page

      before = page.text.to_s
      added = text.start_with?(before) ? text.delete_prefix(before) : text
      { op: text.start_with?(before) ? "append_wiki_page" : "update_wiki_page", text: plain(added), page: page.title }
    end

    # Task lists keep their boxes, so acceptance criteria read as such.
    def plain(markup)
      Assistant::Text.plain(markup.gsub(/^(\s*)[-*] \[ \] /, "\\1☐ ").gsub(/^(\s*)[-*] \[x\] /i, "\\1☑ ")
                                  .gsub(/\*\*(.+?)\*\*/, "\\1").gsub(/\[([^\]]+)\]\([^)]+\)/, "\\1").gsub(/^>[ ]?/, ""))
    end

    # A summary written into a description: the part that is added.
    def description_change(step, text)
      return unless step["op"] == "update_work_package"

      before = WorkPackage.find_by(id: step["id"])&.description.to_s
      return { op: "update_description", text: plain(text) } unless before.present? && text.start_with?(before)

      { op: "append_description", text: plain(text.delete_prefix(before)) }
    end

    # A reminder is about when: the time it goes off, in the reader's zone,
    # and the note it carries.
    def reminders
      @reminders ||= action.steps.filter_map do |step|
        next unless step["op"] == "create_reminder"

        at = Time.zone.parse(step.dig("attributes", "remind_at").to_s) or next
        { at:, note: step.dig("attributes", "note").presence }
      end
    end

    def reminder_time(at) = Assistant::Text.moment(at)

    def spoken_lead(entry) = t("assistant.card.spoken.#{entry[:op]}", page: entry[:page])

    def spoken_limit = compact? ? 280 : nil

    # Where a basis came from, at a glance: read off the record's class in
    # its global id, so a journal on a wiki page shows as a page.
    BASIS_ICONS = { "WorkPackage" => :"issue-opened", "Message" => :"comment-discussion", "WikiPage" => :book,
                    "News" => :megaphone, "Comment" => :comment, "TimeEntry" => :clock, "MeetingAgendaItem" => :people,
                    "Meeting" => :people, "MeetingOutcome" => :people, "Assistant::Conversation" => :"sparkle-fill",
                    "Assistant::Duty" => :tasklist, "Attachment" => :paperclip, "Document" => :file,
                    "Version" => :milestone, "Project" => :project }.freeze

    def basis_icon(entry)
      return :plug if entry.kind.to_s == "mcp"

      model = entry.gid.to_s[%r{\Agid://[^/]+/([^/]+)/}, 1]
      model = journable_type(entry) || "Comment" if model == "Journal"
      BASIS_ICONS.fetch(model, :note)
    end

    def journable_type(entry) = Journal.where(id: entry.gid.to_s[/\d+\z/]).pick(:journable_type)

    def decidable? = action.decidable_by?(user)

    def undoable?
      return false unless action.undoable? && user.logged? && !user.is_a?(AssistantUser)

      user.id == action.decided_by_id || Assistant::Actions::Authority.new(action, user).may_decide?
    end

    def plan_options
      @plan_options ||= action.options.select { it.is_a?(Hash) && it["key"].present? }
    end

    def choosing? = action.proposed? && decidable? && plan_options.size > 1

    # Drafts whose words are the whole point (news, the project status) are
    # edited on the full card before they go out; other cards read the words.
    DRAFT_OPS = %w[publish_news update_project_status send_mail].freeze

    def revisable? = action.proposed? && decidable? && action.steps.any? { DRAFT_OPS.include?(it["op"].to_s) }

    def drafting? = !compact? && !choosing? && revisable?

    def option_summary(option)
      return option["consequence"] if option["consequence"].present?

      Consequences.new(option["preview"] || {}, user:).summary
    end

    def option_input_id(option) = "#{id}-option-#{option['key'].to_s.parameterize}"

    def waiting_for_someone_else? = action.proposed? && !decidable?

    def decider_hint
      return t("assistant.card.waiting_for", name: on_behalf_of.name) if on_behalf_of && on_behalf_of != user

      t("assistant.card.waiting")
    end

    def decided_line
      case status
      when "executed"
        action.decided_by ? t("assistant.card.executed_by", name: action.decided_by.name) : t("assistant.card.executed_itself")
      when "rejected" then action.decided_by && t("assistant.card.rejected_by", name: action.decided_by.name)
      when "undone" then action.undone_by && t("assistant.card.undone_by", name: action.undone_by.name)
      end
    end

    def failure_text = action.error.presence || t("assistant.card.failed_generic")

    def consequences = @consequences ||= Consequences.new(preview, user:)

    delegate :attribute_label, to: :consequences

    LABEL_MARK = "\u0000"

    def change_line(change, with: consequences)
      label = change.url ? link_to(change.label, change.url, data: { turbo_frame: "_top" }) : ERB::Util.html_escape(change.label)
      ERB::Util.html_escape(with.line(change, label: LABEL_MARK)).to_str.sub(LABEL_MARK) { label.to_s }.html_safe
    end

    def undo_presenter = @undo_presenter ||= undo_preview.presenter

    def undo_consequences = @undo_consequences ||= Consequences.new(undo_presenter, user:)

    def undo_failed? = !undo_presenter.success?

    def kept_line(conflict)
      t("assistant.card.conflict", label: conflict["label"], attribute: attribute_label(conflict["attribute"]))
    end

    def slip_sentence(slip) = consequences.slip(slip)

    delegate :affected_names, to: :consequences

    def cascade_limit = compact? ? 2 : 5

    def form_inputs
      [{ name: "variant", value: variant.to_s }, { name: "heading_level", value: @heading_level.to_s },
       *siblings.map { { name: "siblings[]", value: it.to_s } }]
    end

    def approve_path = url_helpers.approve_assistant_action_path(action)

    def reject_path = url_helpers.reject_assistant_action_path(action)

    def revise_path = url_helpers.revise_assistant_action_path(action)

    def undo_path = url_helpers.undo_assistant_action_path(action)

    def show_path = url_helpers.assistant_action_path(action)

    def subject_link
      case action.subject
      when WorkPackage then helpers.link_to("##{action.subject.id} #{action.subject.subject}",
                                            helpers.work_package_path(action.subject))
      when Project then helpers.link_to(action.subject.name, helpers.project_path(action.subject))
      when Meeting then helpers.link_to(action.subject.title, helpers.meeting_path(action.subject))
      end
    end

    def confirm_label
      return t("assistant.draft.publish") if action.steps.any? { it["op"] == "publish_news" }
      return t("assistant.draft.send") if action.steps.any? { it["op"] == "send_mail" }

      action.tier == "t3" ? t("assistant.card.confirm_explicit") : t("assistant.card.confirm")
    end
  end
end
