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

require "digest"

module Assistant
  module Understanding
    # Reads one new message in its conversation and turns what it says into
    # ledger entries. The model proposes; this class keeps only what it can
    # check: the quote must be in the message, people must be project members,
    # dates are computed by DueResolver, updates may only touch listed items.
    class Extractor
      THREAD_LIMIT = 12
      RESTATEMENT_OVERLAP = 0.5
      RESTATEMENT_SHARED = 3
      DISMISSED_EXAMPLES = 8
      EXTRACTED_EVENT = "assistant.understanding.extracted"
      CHANGE_FIELDS = %w[due_date start_date assignee version sprint status priority estimated_hours].freeze
      Source = Data.define(:record, :project, :subject, :author, :stated_at, :text, :internal, :thread)
      Turn = Data.define(:ref, :author, :at, :text)

      def self.for_journal(journal) = for_record(journal)

      def self.for_agenda_item(agenda_item)
        meeting = agenda_item.meeting
        siblings = meeting.agenda_items.where.not(id: agenda_item.id).order(:position).to_a

        new(Source.new(
              record: agenda_item,
              project: meeting.project,
              subject: meeting,
              author: agenda_item.presenter || agenda_item.author || meeting.author,
              stated_at: meeting.start_time,
              text: agenda_text(agenda_item),
              internal: false,
              thread: siblings.map do |item|
                Turn.new(ref: "agenda item ##{item.id}", author: item.presenter || item.author, at: meeting.start_time,
                         text: [item.title, Text.plain(item.notes)].compact_blank.join(": "))
              end
            ))
      end

      # Any other place people write: a comment, a forum post, a wiki edit,
      # news, a news comment, a time entry's comment.
      def self.for_record(record)
        new(Source.new(
              record:,
              project: Sources.project_of(record),
              subject: Sources.subject_of(record),
              author: Sources.author_of(record),
              stated_at: Sources.stated_at(record),
              text: Sources.text_of(record),
              internal: Sources.internal?(record),
              thread: Sources.thread_of(record).map { Turn.new(ref: _1.ref, author: _1.author, at: _1.at, text: _1.text) }
            ))
      end

      # What was said under an agenda item: its title, its notes, and the
      # information outcomes written down during the meeting. Decision outcomes
      # are left out because MeetingCapture already records them as typed.
      def self.agenda_text(agenda_item)
        outcomes = agenda_item.outcomes.select(&:information_kind?).map { |outcome| Text.plain(outcome.notes) }
        [OwnWords.agenda_title(agenda_item), Text.plain(OwnWords.agenda_notes(agenda_item)), *outcomes].compact_blank.join("\n")
      end

      def initialize(source, llm: nil)
        @source = source
        @llm = llm
      end

      attr_reader :source

      def call
        return skip!("empty") if source.text.blank?
        return existing if already_extracted?

        supersede_previous_reading!
        data = llm.json(system: Prompt::SYSTEM, user: user_message)
        created = nil
        changes = said_changes(data["changes"])
        signals = said_signals(data["signals"])

        Intent.transaction do
          updates = Array(data["updates"]).map { |update| update.to_h.stringify_keys }
          proposals = without_restatements(Array(data["items"]), updates)
          created = build_items(proposals)
          apply_updates(updates, created)
          record_extraction!("succeeded", items_count: created.size)
        end

        OpenProject::Notifications.send(EXTRACTED_EVENT, source: source.record, subject: source.subject, items: created,
                                                         changes:, signals:)
        created
      rescue Assistant::Llm::NotConfigured
        skip!("not_configured")
      rescue Assistant::Llm::Error => e
        record_extraction!("failed", error: e.message)
        raise
      end

      private

      def llm = @llm ||= Assistant::Llm.new(purpose: "understanding", project:, config: Assistant::Llm.base_config)

      def project = source.project

      def digest = @digest ||= Digest::SHA256.hexdigest(source.text)

      def extraction
        @extraction ||= Assistant::Extraction.find_or_initialize_by(source: source.record, extractor_version: Prompt::VERSION)
      end

      def already_extracted?
        extraction.persisted? && extraction.status == "succeeded" && extraction.source_digest == digest
      end

      def existing = Intent.where(source: source.record).to_a

      def skip!(reason)
        record_extraction!("skipped", error: reason)
        []
      end

      def record_extraction!(status, items_count: 0, error: nil)
        extraction.update!(project:, source_digest: digest, status:, items_count:, error:)
      rescue ActiveRecord::RecordNotUnique
        @extraction = nil
        extraction.update!(project:, source_digest: digest, status:, items_count:, error:)
      end

      # An edited message is read again. What the earlier reading produced and
      # nobody has touched since is dropped; anything a person confirmed or acted
      # on stays, because that person's action is the record now.
      def supersede_previous_reading!
        return unless extraction.persisted? && extraction.source_digest != digest

        Intent.where(source: source.record, status: Intent::LIVE_STATUSES, work_package_id: nil, answered_by_id: nil,
                     parent_id: nil)
              .where.not(id: Intent.where.not(supersedes_id: nil).select(:supersedes_id))
              .destroy_all
      end

      def members
        @members ||= begin
          users = project.users.where(status: Principal.statuses[:active]).to_a
          users |= [source.author] if source.author.is_a?(User)
          users.index_by(&:id)
        end
      end

      def open_items
        @open_items ||= Intent.live.where(project:, subject: source.subject)
                            .where.not(source: source.record).order(:stated_at).limit(40).to_a
      end

      def user_message
        <<~TEXT
          PROJECT: #{project.name}
          WHERE: #{subject_line}
          TODAY (date the message was written): #{stated_on.iso8601}

          MEMBERS:
          #{members.values.map { |u| "- id #{u.id}: #{u.name}" }.join("\n")}

          OPEN ITEMS:
          #{open_items_text}

          THIS TEAM SAID THESE WERE NOT COORDINATION ACTS (do not record similar ones):
          #{dismissed_text}

          CONVERSATION SO FAR:
          #{thread_text}

          #{change_context}
          #{spoken? ? "NEW MESSAGE by #{author_line}" : 'NEW AGENDA ITEM (typed into the meeting, not said by one person)'} on #{stated_on.iso8601}:
          #{source.text}
        TEXT
      end

      def subject_line
        case source.subject
        when WorkPackage
          wp = source.subject
          parts = ["work package ##{wp.id} \"#{wp.subject}\"", "status #{wp.status&.name}"]
          parts << "assignee #{wp.assigned_to.name} (id #{wp.assigned_to_id})" if wp.assigned_to
          parts << "start #{wp.start_date.iso8601}" if wp.start_date
          parts << "due #{wp.due_date.iso8601}" if wp.due_date
          parts << "sprint #{wp.sprint.name}" if wp.respond_to?(:sprint) && wp.sprint
          parts << "version #{wp.target_versions.first.name}" if wp.target_versions.any?
          parts.join(", ")
        when Meeting
          "meeting \"#{source.subject.title}\" on #{source.subject.start_time&.to_date&.iso8601}"
        when ::Message
          "forum \"#{source.subject.forum.name}\", topic \"#{source.subject.subject}\""
        when WikiPage
          "wiki page \"#{source.subject.title}\"#{' (edit note)' unless source.record.try(:initial?)}"
        when News
          "news \"#{source.subject.title}\""
        when Project
          "time entry comment in project \"#{source.subject.name}\""
        end
      end

      def change_context
        lines = []
        lines << "LINKED WORK PACKAGE: #{work_package_line(linked_work_package)}" if linked_work_package && !spoken?
        versions = project.shared_versions.where(status: "open").order(:effective_date).pluck(:name)
        lines << "OPEN VERSIONS: #{versions.join('; ')}" if versions.any?
        sprints = defined?(::Sprint) ? ::Sprint.where(project:).order(:start_date).last(6).map(&:name) : []
        lines << "SPRINTS: #{sprints.join('; ')}" if sprints.any?
        lines.join("\n")
      end

      def work_package_line(wp)
        parts = ["##{wp.id} \"#{wp.subject}\"", "status #{wp.status&.name}"]
        parts << "assignee #{wp.assigned_to.name} (id #{wp.assigned_to_id})" if wp.assigned_to
        parts << "start #{wp.start_date.iso8601}" if wp.start_date
        parts << "due #{wp.due_date.iso8601}" if wp.due_date
        parts.join(", ")
      end

      def linked_work_package
        return unless source.record.is_a?(MeetingAgendaItem)

        @linked_work_package ||= source.record.work_package ||
                                 source.record.outcomes.find(&:linked_work_package?)&.work_package
      end

      # What the message asks to change on a work package. Only the shape and
      # the quote are checked here; which work package, person or version the
      # words mean is decided by whoever acts on it.
      def said_changes(raw)
        Array(raw).filter_map do |change|
          change = change.to_h.stringify_keys
          quote = change["quote"].to_s.strip
          next unless CHANGE_FIELDS.include?(change["field"]) && Text.contains?(source.text, quote)

          change.slice("target", "field", "value", "shift", "certainty").merge("quote" => quote)
        end
      end

      SIGNAL_TYPES = %w[dependency split time_off time_spent risk knowledge].freeze

      # Other things worth keeping that the message said; checked the same way.
      def said_signals(raw)
        Array(raw).filter_map do |signal|
          signal = signal.to_h.stringify_keys
          quote = signal["quote"].to_s.strip
          next unless SIGNAL_TYPES.include?(signal["type"]) && Text.contains?(source.text, quote)

          signal.merge("quote" => quote)
        end
      end

      def author_line
        author = source.author
        author.is_a?(User) ? "#{author.name} (id #{author.id})" : "unknown"
      end

      def open_items_text
        return "(none)" if open_items.empty?

        open_items.map do |item|
          due = item.said_due_on ? ", due #{item.said_due_on.iso8601}" : ""
          owner = item.owner ? ", owner id #{item.owner_id}" : ""
          "- id #{item.id} [#{item.kind}#{owner}#{due}] #{item.title} — \"#{item.quote}\""
        end.join("\n")
      end

      def dismissed_text
        quotes = Intent.where(project:, status: "dismissed").order(updated_at: :desc)
                     .limit(DISMISSED_EXAMPLES).pluck(:kind, :quote)
        return "(none yet)" if quotes.empty?

        quotes.map { |kind, quote| "- #{kind}: \"#{quote}\"" }.join("\n")
      end

      def thread_text
        return "(this is the first message)" if source.thread.empty?

        source.thread.map do |turn|
          name = turn.author.respond_to?(:name) ? "#{turn.author.name} (id #{turn.author.id})" : "unknown"
          "[#{turn.ref}] #{turn.at&.to_date&.iso8601} #{name}: #{turn.text.truncate(600)}"
        end.join("\n")
      end

      def stated_on
        zone = source.author.respond_to?(:time_zone) && source.author.time_zone ? source.author.time_zone : Time.zone
        source.stated_at.in_time_zone(zone).to_date
      end

      # A message that moves or closes an open item does not also open a new one
      # for the same work, even when the model reports both.
      def without_restatements(proposals, updates)
        touched = updates.select { |u| u["action"].in?(%w[renegotiated done withdrawn]) }
                         .filter_map { |u| open_items.find { |item| item.id == u["item_id"].to_i } }
        return proposals if touched.empty?

        proposals.reject do |proposal|
          proposal = proposal.to_h.stringify_keys
          next false unless proposal["kind"].in?(%w[commitment deferral])

          touched.any? { |item| restates?(item, proposal) }
        end
      end

      def restates?(item, proposal)
        owner_id = proposal["owner_id"].presence&.to_i
        return false if owner_id && item.owner_id && owner_id != item.owner_id

        existing = "#{item.title} #{item.quote}"
        proposed = "#{proposal['title']} #{proposal['quote']}"
        forward, shared = Text.overlap(existing, proposed)
        backward, = Text.overlap(proposed, existing)
        shared >= RESTATEMENT_SHARED || [forward, backward].max >= RESTATEMENT_OVERLAP
      end

      def build_items(proposals)
        proposals.filter_map { |proposal| build_item(proposal.to_h.stringify_keys) }
      end

      def build_item(data)
        kind = data["kind"].to_s
        return unless Intent::KINDS.include?(kind)

        quote = data["quote"].to_s.strip
        return unless Text.contains?(source.text, quote)

        owner = member(data["owner_id"]) || (kind.in?(%w[decision question]) && spoken? ? author_user : nil)
        strength = Intent::STRENGTHS.include?(data["strength"]) ? data["strength"] : "tentative"
        resolved = resolver.call(data["due"])

        item = Intent.create!(
          project:, kind:, status: kind == "decision" ? "active" : "open", strength:,
          title: data["title"].to_s.strip.presence&.truncate(200) || quote.truncate(120),
          quote:, owner:, counterparty: counterparty_for(data, owner),
          source: source.record, subject: source.subject,
          said_due_expression: data["due_expression"].to_s.strip.presence,
          said_due_on: kind.in?(%w[commitment deferral]) ? resolved.due_on : nil,
          due_anchor: resolved.anchor,
          internal: source.internal, external_exposure: data["external_exposure"] == true,
          stated_at: source.stated_at, extractor_version: Prompt::VERSION
        )
        item
      end

      def counterparty_for(data, owner)
        counterparty = member(data["counterparty_id"])
        counterparty == owner ? nil : counterparty
      end

      def apply_updates(updates, created)
        by_id = open_items.index_by(&:id)

        updates.each do |update|
          target = by_id[update["item_id"].to_i]
          next if target.nil?

          apply_update(target, update, created)
        end
      end

      def apply_update(target, update, created)
        action = update["action"].to_s

        case action
        when "objection"
          quote = update["quote"].to_s.strip
          return unless target.kind == "decision" && Text.contains?(source.text, quote)

          objection = Intent.create!(
            project:, kind: "question", status: "open", strength: "firm",
            title: quote.truncate(120), quote:, owner: author_user, counterparty: target.owner,
            source: source.record, subject: source.subject, internal: source.internal,
            parent: target, stated_at: source.stated_at, extractor_version: Prompt::VERSION
          )
          created << objection
        when "exposed"
          return if target.external_exposure

          target.update!(external_exposure: true)
        when "superseded"
          return unless target.kind == "decision"

          replacement = created.find { |item| item.kind == "decision" }
          target.settle!("superseded")
          replacement&.update!(supersedes: target)
        when "answered"
          return unless target.kind == "question"

          target.update!(status: "answered", resolved_at: Time.current, answered_by: source.record)
        when "done", "withdrawn"
          return unless target.commitment_like?
          return unless may_speak_for?(target)

          target.settle!(action)
          when "renegotiated"
          return unless target.commitment_like? && may_speak_for?(target)

          resolved = resolver.call(update["due"])
          return if resolved.due_on.nil?

          target.move_to!(resolved.due_on, update["due_expression"].to_s.strip.presence)
        end
      end

      # Only the owner closes or moves their own commitment from a comment. A
      # third person writing "this is done" leaves it to the owner to agree.
      def may_speak_for?(target)
        target.owner_id.nil? || target.owner_id == author_user&.id
      end

      def member(id)
        members[id.to_i] if id.present?
      end

      def author_user
        source.author.is_a?(User) ? source.author : nil
      end

      # A comment, a post, an edit note is said by its author. An agenda item
      # is only typed by someone; what is on it was agreed by the room.
      def spoken? = !source.record.is_a?(MeetingAgendaItem)

      def resolver
        @resolver ||= DueResolver.new(project:, stated_on:,
                                      work_package: source.subject.is_a?(WorkPackage) ? source.subject : nil)
      end

    end
  end
end
