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
  # An answer as the reader sees it: the platform's own markdown rendering (which
  # turns #69 into a link with its hover card and strips anything unsafe),
  # then every other object the answer names becomes a link too. Only what
  # `user` may see is linked; anything else stays the plain words it was.
  class Linkify
    include OpenProject::TextFormatting

    MIN_LENGTH = 2
    WIKI_MIN_LENGTH = 3
    SKIPPED = %w[a code pre script style].freeze
    TEXT_NODES = ".//text()[not(#{SKIPPED.map { "ancestor::#{it}" }.join(' or ')})]".freeze
    WORK_PACKAGE_HREF = %r{\A/work_packages/(\d+)\z}
    BARE_WORK_PACKAGE = /(?<![A-Za-z0-9_&#\/])#(\d{1,9})(?![A-Za-z0-9_]|\.\d)/
    QUOTES = { "“" => "”", "「" => "」", "『" => "』", '"' => '"' }.freeze

    Entry = Data.define(:text, :build)

    def self.call(text, user:, project: nil) = new(text, user:, project:).call

    def initialize(text, user:, project:)
      @text = text.to_s
      @user = user
      @project = project
    end

    def call
      User.execute_as(@user) do
        fragment = Nokogiri::HTML::DocumentFragment.parse(without_empty_links(rendered))
        link_bare_work_packages(fragment)
        absorb_work_package_titles(fragment)
        link_names(fragment)
        fragment.css("a[href^='/']").each { it["data-turbo-frame"] = "_top" }
        fragment.to_html.html_safe # rubocop:disable Rails/OutputSafety
      end
    end

    private

    def rendered = format_text(@text, project: @project, only_path: true, current_user: @user)

    # `[#12 Subject](/work_packages/12)` comes out as an empty link followed
    # by the #12 macro link: the macro runs inside the link text. An empty
    # link is a stop with nothing to read, so it goes; heading permalinks are
    # empty on purpose and stay.
    def without_empty_links(html)
      return html unless html.include?("></a>")

      fragment = Nokogiri::HTML::DocumentFragment.parse(html)
      fragment.css("a:not(.op-uc-link_permalink)").each { it.remove if it.children.empty? }
      fragment.to_html
    end

    # The host only recognises #id after a space or an opening bracket, so
    # "下游：#70" and "（#70" are left as text; those get their link here.
    def link_bare_work_packages(fragment)
      nodes = fragment.xpath(TEXT_NODES).select { it.text.match?(BARE_WORK_PACKAGE) }
      return if nodes.empty?

      visible = visible_subjects(bare_ids(nodes)).keys.to_set
      nodes.each do |node|
        node.replace(substitute(node.text, BARE_WORK_PACKAGE) { |match| work_package_link(match, visible) })
      end
    end

    def bare_ids(nodes) = nodes.flat_map { |node| node.text.scan(BARE_WORK_PACKAGE).flatten.map(&:to_i) }.uniq

    def work_package_link(match, visible)
      id = match[1].to_i
      return ERB::Util.html_escape(match[0]) unless visible.include?(id)

      helpers.link_to(match[0], helpers.work_package_path(id), target: "_top", class: "issue work_package op-uc-link",
                                                               data: { hover_card_trigger_target: "trigger",
                                                                       hover_card_url: helpers.hover_card_work_package_path(id) })
    end

    # The platform links any #id it finds; whether the reader may open it is
    # decided here, and a title is only ever taken from a visible one.
    def absorb_work_package_titles(fragment)
      links = fragment.css("a.work_package").index_with { it["href"].to_s[WORK_PACKAGE_HREF, 1]&.to_i }
      return if links.empty?

      subjects = visible_subjects(links.values.compact)
      links.each { |link, id| subjects.key?(id) ? absorb_title(link, subjects[id]) : unlink(link) }
    end

    def visible_subjects(ids) = WorkPackage.visible(@user).where(id: ids).pluck(:id, :subject).to_h

    def unlink(link) = link.replace(Nokogiri::XML::Text.new(link.text, link.document))

    def absorb_title(link, subject)
      following = link.next_sibling
      return if subject.blank? || !following&.text?

      found = title_after(following.text, subject)
      return unless found

      link.content = "#{link.text} #{subject}"
      following.content = following.text.delete_prefix(found)
    end

    def title_after(text, subject)
      escaped = Regexp.escape(subject)
      quoted = text.match(/\A\s*(["“「『])#{escaped}(["”」』])/)
      return quoted[0] if quoted && QUOTES[quoted[1]] == quoted[2]

      text[/\A\s*#{escaped}(?![A-Za-z0-9_])/]
    end

    def link_names(fragment)
      entries = entries_for(fragment.text)
      return if entries.empty?

      pattern = pattern_for(entries.keys)
      fragment.xpath(TEXT_NODES).each do |node|
        next unless node.text.match?(pattern)

        node.replace(linked(node.text, pattern, entries))
      end
    rescue StandardError => e
      Rails.logger.warn("[assistant] linkify: #{e.class} #{e.message}")
    end

    def linked(text, pattern, entries)
      substitute(text, pattern) { |match| entries.fetch(match[0]).build.call(match[0]) }
    end

    def substitute(text, pattern)
      html = +""
      position = 0
      text.scan(pattern) do
        match = Regexp.last_match
        html << ERB::Util.html_escape(text[position...match.begin(0)]) << yield(match)
        position = match.end(0)
      end
      html << ERB::Util.html_escape(text[position..])
    end

    def pattern_for(texts)
      alternatives = texts.sort_by { -it.length }.map { Regexp.escape(it) }.join("|")
      /(?<![A-Za-z0-9_])(?:#{alternatives})(?![A-Za-z0-9_]|\.\d)/
    end

    def entries_for(plain)
      return {} if plain.length < MIN_LENGTH

      [*versions(plain), *sprints(plain), *meetings(plain), *wiki_pages(plain), *people(plain), *projects(plain)]
        .select { it.text.length >= MIN_LENGTH }
        .each_with_object({}) { |entry, all| all[entry.text] ||= entry }
    end

    def versions(plain)
      visible = Version.visible(@user)
      named = visible.where("strpos(?, versions.name) > 0", plain).to_a
      named.map { link_entry(it.name, helpers.version_path(it), "version") } + version_tokens(visible, plain)
    end

    # "v2.0 团队版" is also said as "v2.0" — as long as only one version
    # starts that way.
    def version_tokens(visible, plain)
      visible.where("strpos(?, split_part(versions.name, ' ', 1)) > 0", plain).filter_map do |version|
        token = version.name.split(/\s+/, 2).first
        next unless token != version.name && token.length >= 3 && token.match?(/\d/)
        next if visible.where("split_part(versions.name, ' ', 1) = ?", token).count != 1

        link_entry(token, helpers.version_path(version), "version")
      end
    end

    def sprints(plain)
      Sprint.visible(@user).where("strpos(?, sprints.name) > 0", plain).includes(:project).map do |sprint|
        home = @project if @project && sprint.visible_to?(@project)
        link_entry(sprint.name, helpers.project_backlogs_backlog_path(home || sprint.project), "sprint")
      end
    end

    def meetings(plain)
      Meeting.visible(@user).where(template: false).where("strpos(?, meetings.title) > 0", plain).to_a
             .group_by(&:title).map do |title, same|
        meeting = same.min_by { (it.start_time - Time.current).abs }
        link_entry(title, helpers.meeting_path(meeting), "meeting")
      end
    end

    def wiki_pages(plain)
      WikiPage.visible(@user).where("char_length(wiki_pages.title) >= ?", WIKI_MIN_LENGTH)
              .where("strpos(?, wiki_pages.title) > 0", plain).to_a.group_by(&:title).map do |title, same|
        page = same.find { it.project == @project } || same.first
        link_entry(title, helpers.project_wiki_path(page.project, page), "wiki")
      end
    end

    def people(plain)
      User.visible(@user).where(status: %i[active registered invited])
          .where("(users.firstname <> '' AND strpos(:t, users.firstname) > 0) OR " \
                 "(users.lastname <> '' AND strpos(:t, users.lastname) > 0)", t: plain).flat_map do |person|
        person_names(person).select { plain.include?(it) }.map { |name| person_entry(person, name) }
      end
    end

    def person_names(person)
      [person.name, "#{person.lastname}#{person.firstname}", "#{person.firstname}#{person.lastname}",
       "#{person.firstname} #{person.lastname}", (person.firstname if first_name_unique?(person))]
        .compact.uniq.select { it.length >= MIN_LENGTH }
    end

    def first_name_unique?(person)
      person.firstname.match?(/\A[A-Z][a-z]+\z/) && User.visible(@user).not_builtin.where(firstname: person.firstname).one?
    end

    def person_entry(person, name)
      Entry.new(name, ->(text) { helpers.link_to_user(person, only_path: true, name: text, class: "op-uc-link", target: "_top") })
    end

    def projects(plain)
      Project.visible(@user).where("strpos(?, projects.name) > 0", plain).map do |project|
        link_entry(project.name, helpers.project_path(project), "project")
      end
    end

    def link_entry(text, path, kind)
      options = { class: "op-uc-link assistant-link assistant-link--#{kind}", target: "_top" }
      Entry.new(text, ->(label) { helpers.link_to(label, path, options) })
    end

    def helpers = @helpers ||= ApplicationController.helpers
  end
end
