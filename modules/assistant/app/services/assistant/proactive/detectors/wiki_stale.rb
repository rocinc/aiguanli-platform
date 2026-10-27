# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  module Proactive
    module Detectors
      # Wiki pages that went stale (04 D4 算): a page that names work
      # packages which have since closed, moved to another version or been
      # deleted, while the page itself stayed as it was. Code reads the #ids
      # on the page and compares with the work packages now; the page's last
      # editor gets one brief line per page, with what changed, at most
      # monthly. Pages nothing links to and that nobody edited for a long
      # time are listed in the same notice as orphans worth a look.
      class WikiStale < Base
        STALE_AFTER = 30.days
        ORPHAN_AFTER = 180.days

        def candidates
          return [] unless project.wiki

          stale = pages.filter_map { |page| changes_since(page).presence&.then { [page, it] } }
          stale.filter_map do |page, changed|
            editor = editor_of(page) or next
            candidate(
              fingerprint: "page#{page.id}:#{today.strftime('%Y-%m')}", recipient: editor, subject: page, nature: :object,
              channel: "brief", certainty: :fact,
              headline: t("headline", page: page.title.truncate(40), count: changed.size),
              because: [*changed.first(6), (t("orphans", list: orphans.first(5).map(&:title).join("、")) if orphans.any?)].compact,
              impact: { people: 1 }
            )
          end
        end

        private

        def pages = @pages ||= project.wiki.pages.includes(:author).to_a

        # What happened to the work packages a page names, after the page
        # was last edited.
        def changes_since(page)
          ids = page.text.to_s.scan(/(?<![\w&])#(\d+)\b/).flatten.map(&:to_i).uniq.first(40)
          return [] if ids.empty? || page.updated_at > STALE_AFTER.ago

          found = WorkPackage.where(id: ids).includes(:status).index_by(&:id)
          ids.filter_map do |id|
            wp = found[id]
            next t("gone", ref: "##{id}") unless wp
            next unless wp.updated_at > page.updated_at

            if wp.closed? then t("closed", ref: "##{id}", subject: wp.subject.truncate(30), status: wp.status.name)
            elsif (version = Assistant::Facts.version_of(wp)) && !page.text.to_s.include?(version.name)
              t("moved", ref: "##{id}", version: version.name)
            end
          end
        end

        def orphans
          @orphans ||= begin
            linked = pages.flat_map { it.text.to_s.scan(/\[\[([^\]|#]+)/).flatten.map { |title| title.strip.downcase } }
            pages.select do |page|
              page.parent_id.nil? && page.updated_at < ORPHAN_AFTER.ago && linked.exclude?(page.title.downcase) &&
                page.children.none?
            end
          end
        end

        def editor_of(page)
          last = page.journals.reorder(version: :desc).includes(:user).first&.user
          [last, page.author].find { it.is_a?(User) && it.logged? && it.active? && !it.is_a?(AssistantUser) } || leads.first
        end
      end
    end
  end
end
