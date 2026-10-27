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

module Assistant
  # A newcomer's first page about a project (06 S9): what the project is and
  # where it stands, the work they take over and what to know about each, the
  # decisions that shape it, the people to meet and the pages to read first.
  # The onboarding duty drafts it as a wiki page for the delegator to publish.
  # The facts and their links are computed here; one model call only words
  # them, so every line keeps the link it came from even when the model is
  # unavailable or says something else.
  #
  # to_h: { "project" => {...}, "work_packages" | "decisions" | "people" | "wiki" => [item] }
  # item: { "ref", "label", "url", "facts" => [..], "note" }
  class Onboarding
    LIMITS = { work_packages: 5, decisions: 6, people: 4, wiki: 3 }.freeze

    SYSTEM = <<~PROMPT
      You welcome a new member to a project team. You get the facts about the project as JSON: the
      project, the work packages they take over, recent decisions, people to meet and wiki pages to
      read, each with a "ref". Write in the language given.
      Answer as JSON: {"summary": "...", "notes": {"<ref>": "..."}}.
      - summary: two sentences, what the project is and where it stands now.
      - notes: for each ref, one short sentence (at most 25 words) the facts do not already say: how
        the item connects to the person's own work packages or to another item listed. The facts are
        shown next to your note, so never restate them, the title or the ref. Use only the facts
        given; never add numbers, names or dates that are not in them. Leave a ref out when there is
        no such connection; most refs should have no note.
      - Never guess anyone's gender from a name: refer to people by name or with neutral wording,
        never he/she (他/她).
    PROMPT

    def initialize(user:, project:, today: Date.current, llm: nil)
      @user = user
      @project = project
      @today = today
      @llm = llm
    end

    attr_reader :user, :project, :today

    def to_h
      @to_h ||= { "project" => project_facts, "work_packages" => work_packages, "decisions" => decisions,
                  "people" => people, "wiki" => wiki }
    end

    # The facts in words. Falls back to the facts alone when there is no
    # model, no budget left, or the model does not answer.
    def written
      data = to_h.deep_dup
      words = words_for(data)
      data["project"]["summary"] = words["summary"].to_s.strip.presence
      notes = words["notes"].to_h
      LIMITS.each_key do |section|
        data[section.to_s].each { |item| item["note"] = notes[item["ref"]].to_s.strip.presence&.truncate(240) }
      end
      data.merge("written" => words.present?)
    end

    def empty? = LIMITS.keys.all? { to_h[it.to_s].empty? }

    def page_title = t("page", name: user.name)

    # Every line ends in the link it came from.
    def markdown(data)
      head = ["## #{t('title', project: project.name)}",
              data.dig("project", "summary") || data.dig("project", "facts").to_a.join("; "),
              link(data["project"])]
      sections = LIMITS.keys.filter_map do |section|
        items = data[section.to_s]
        next if items.empty?

        lines = items.map { |item| "- **#{link(item)}**: #{[item['facts'].join('; '), item['note']].compact_blank.join(' — ')}" }
        ["### #{t("sections.#{section}")}", *lines].join("\n")
      end
      [*head.compact_blank, *sections].join("\n\n")
    end

    private

    def link(item) = item["url"] ? "[#{item['label'].to_s.gsub(/[\[\]]/, '')}](#{item['url']})" : item["label"]

    def helpers = @helpers ||= OpenProject::StaticRouting::StaticUrlHelpers.new

    def words_for(data)
      return {} unless Assistant::Llm.configured? && !Assistant::Usage.near_budget?(project:)

      input = { "language" => I18n.locale.to_s }.merge(data)
      words = llm.json(system: SYSTEM, user: JSON.generate(input), max_tokens: 2000)
      Rails.logger.warn("[assistant] onboarding words empty for #{user.id} in #{project.id}") if words.blank?
      words
    rescue Assistant::Llm::Error => e
      Rails.logger.warn("[assistant] onboarding words for #{user.id} in #{project.id}: #{e.message}")
      {}
    end

    def llm = @llm ||= Assistant::Llm.new(purpose: "onboarding", user:, project:)

    def project_facts
      { "ref" => "project", "label" => project.name, "url" => helpers.project_path(project),
        "facts" => [description, phase_line, status_line, version_line].compact, "summary" => nil }
    end

    def description
      text = Assistant::Text.plain(project.description).squish
      text.presence && t("project_description", text: text.truncate(200))
    end

    def phase_line
      return unless user.allowed_in_project?(:view_project_phases, project)

      phases = project.available_phases.select(&:start_date)
      phase = phases.detect { |current| current.finish_date && (current.start_date..current.finish_date).cover?(today) } ||
              phases.detect { |upcoming| upcoming.start_date > today }
      return unless phase

      t("phase", name: phase.name, from: date(phase.start_date), to: date(phase.finish_date))
    end

    def status_line
      return if project.status_code.blank?

      t("status", status: I18n.t("activerecord.attributes.project.status_codes.#{project.status_code}",
                                 default: project.status_code.to_s.humanize),
                  explanation: Assistant::Text.plain(project.status_explanation).squish.truncate(120).presence || "–")
    end

    def version_line
      readiness = next_version&.then { Assistant::Facts::VersionReadiness.new(it) }
      return unless readiness

      name = next_version.name
      due = date(next_version.effective_date)
      return t("version_empty", name:, date: due) if readiness.work_packages.empty?

      t("version", name:, date: due, done: readiness.done_ratio, open: readiness.open.size)
    end

    def next_version
      return @next_version if defined?(@next_version)

      @next_version = Version.where(project:, status: "open").where.not(effective_date: nil)
                             .where(effective_date: today..).order(:effective_date).first
    end

    def own_work_packages
      @own_work_packages ||= WorkPackage.visible(user).where(project:)
                                        .where("assigned_to_id = :id OR responsible_id = :id", id: user.id)
                                        .where.not(status_id: Assistant::Facts.closed_status_ids)
                                        .includes(:status).order(Arel.sql("due_date ASC NULLS LAST"), :id).to_a
    end

    def work_packages
      own_work_packages.first(LIMITS[:work_packages]).map do |wp|
        item("wp-#{wp.id}", "##{wp.id} #{wp.subject}", helpers.work_package_path(wp), know_about(wp))
      end
    end

    # What a person taking this over needs: where it stands, what was settled
    # or is still asked on it, who had it before, what it waits for.
    def know_about(wp) # rubocop:disable Naming/MethodParameterName
      status = wp.status.name
      lines = [wp.due_date ? t("wp_state", status:, due: date(wp.due_date)) : t("wp_state_undated", status:)]
      items = views.visible.where(subject: wp).where.not(status: "dismissed").to_a
      lines.concat(items.select { it.kind == "decision" && it.status == "active" }.first(2)
                        .map { t("wp_decision", title: it.title.truncate(60), by: it.owner&.name || "–") })
      lines.concat(items.select { it.kind == "question" && it.status == "open" }.first(2)
                        .map { t("wp_question", title: it.title.truncate(60), by: it.owner&.name || "–") })
      before = earlier_owners(wp)
      lines << t("wp_before", names: before.map(&:name).join(t("separator"))) if before.any?
      blockers = Relation.where(relation_type: "blocks", to_id: wp.id).includes(:from).map(&:from)
                         .select { it.visible?(user) && Assistant::Facts.open?(it) }
      lines << t("wp_blocked", refs: blockers.map { "##{it.id}" }.join(t("separator"))) if blockers.any?
      comments = wp.journals.where.not(notes: [nil, ""]).count
      lines << t("wp_thread", count: comments) if comments.positive?
      lines
    end

    def earlier_owners(wp) # rubocop:disable Naming/MethodParameterName
      ids = Assistant::Facts::History.new(wp).changes.select { it.attribute == "assigned_to_id" && it.from }.map(&:from)
      User.active.where(id: ids.uniq - [user.id]).where.not(type: "AssistantUser").to_a
    end

    def views = @views ||= Assistant::Said.new(user, today:)

    def decisions
      views.decisions(project).where(status: "active").includes(:source, :owner).order(stated_at: :desc).limit(LIMITS[:decisions]).map do |decision|
        url = Assistant::Provenance.url_for_basis("gid" => decision.source&.to_gid&.to_s) ||
              (decision.subject.is_a?(WorkPackage) ? helpers.work_package_path(decision.subject) : nil)
        facts = ["“#{decision.quote.to_s.truncate(120)}”",
                 t("decided_by", name: decision.owner&.name || "–", date: date(decision.stated_at.to_date))]
        facts << t("on", label: label(decision.subject)) if decision.subject
        item("decision-#{decision.id}", decision.title, url, facts)
      end
    end

    # The collaboration graph around this person's work: who leads, who had
    # their work before, whose work theirs waits on or holds up, who talks on
    # it, who answers the team's questions.
    def people
      scores = Hash.new { |h, k| h[k] = { score: 0, facts: [] } }
      Assistant::Proactive::Routing.leads(project).each { add(scores, it.id, 3, t("why_lead")) }
      own_work_packages.each do |wp|
        earlier_owners(wp).each { add(scores, it.id, 4, t("why_before", ref: "##{wp.id}")) }
        neighbours(wp).each { |other, line| add(scores, other.assigned_to_id, 3, line) }
        wp.journals.unscope(:order).where.not(notes: [nil,
                                                      ""]).where.not(user_id: user.id).group(:user_id).count.each do |id, count|
          add(scores, id, count, t("why_comments", count:, ref: "##{wp.id}"))
        end
      end
      answers.each { |id, count| add(scores, id, count * 2, t("why_answers", count:)) }

      members = Assistant::Proactive::Routing.people(project).reject { it.id == user.id }.index_by(&:id)
      scores.select { |id, _| members[id] }.sort_by { |_, s| -s[:score] }.first(LIMITS[:people]).map do |id, s|
        person = members[id]
        item("person-#{id}", person.name, helpers.user_path(person), s[:facts].uniq.first(3))
      end
    end

    def add(scores, user_id, score, fact)
      return if user_id.nil? || user_id == user.id

      scores[user_id][:score] += score
      scores[user_id][:facts] << fact
    end

    def neighbours(wp) # rubocop:disable Naming/MethodParameterName
      Relation.of_work_package(wp).where(relation_type: %w[blocks precedes follows]).includes(:from, :to).filter_map do |relation|
        other = relation.from_id == wp.id ? relation.to : relation.from
        next unless other&.assigned_to_id && other.visible?(user)

        waits = (relation.relation_type == "follows") == (relation.from_id == wp.id)
        [other, t(waits ? "why_waits_on" : "why_waits_for", ref: "##{wp.id}", other: "##{other.id}")]
      end
    end

    def answers
      Assistant::Intent.where(project:, answered_by_type: "Journal")
                       .joins("JOIN journals ON journals.id = assistant_intents.answered_by_id")
                       .group("journals.user_id").count
    end

    # Pages about the work this person takes over, else the start page and
    # what the team edited last.
    def wiki
      return [] unless project.wiki && user.allowed_in_project?(:view_wiki_pages, project)

      pages = project.wiki.pages.to_a
      topic = own_work_packages.map(&:subject).join(" ")
      ranked = pages.map { [it, topic.present? ? Assistant::Text.overlap("#{it.title} #{it.text.to_s.first(600)}", topic).first : 0] }
      matching = ranked.select { |_, share| share >= Assistant::Facts::Expertise::MIN_MATCH }.sort_by { -it.last }.map(&:first)
      start = pages.find { it.title == project.wiki.start_page }
      rest = pages.sort_by { -it.updated_at.to_i }
      (matching + [start] + rest).compact.uniq.first(LIMITS[:wiki]).map do |page|
        facts = [t("wiki_updated", date: date(page.updated_at.to_date))]
        facts.unshift(t("wiki_about_yours")) if matching.include?(page)
        facts.unshift(t("wiki_start")) if page == start
        item("wiki-#{page.id}", page.title, helpers.project_wiki_path(project, page), facts)
      end
    end

    def item(ref, label, url, facts) = { "ref" => ref, "label" => label, "url" => url, "facts" => facts, "note" => nil }

    def label(record)
      case record
      when WorkPackage then "##{record.id} #{record.subject.truncate(40)}"
      when Project then record.name
      else record.try(:title) || record.try(:name) || record.to_s
      end
    end

    def date(value) = value ? Assistant::Text.day(value) : "–"

    def t(key, **) = I18n.t("assistant.onboarding.#{key}", **)
  end
end
