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
  # Where a change or a claim comes from: a quote in a comment, a meeting
  # agenda item, a conversation, a duty or a computed fact.
  Basis = Data.define(:kind, :gid, :quote, :label) do
    def self.from_h(hash)
      hash = hash.to_h.stringify_keys
      new(kind: hash["kind"], gid: hash["gid"], quote: hash["quote"], label: hash["label"])
    end

    def self.for(record, quote: nil, label: nil)
      new(kind: record.class.name.underscore, gid: record.to_gid.to_s, quote:, label: label || describe(record))
    end

    def self.describe(record)
      case record
      when Journal then describe_journal(record)
      when ::Comment then I18n.t("assistant.basis.news_comment", title: record.commented.try(:title).to_s.truncate(40),
                                                               date: short_date(record.created_at))
      when TimeEntry then I18n.t("assistant.basis.time_entry", user: record.user&.name, date: Assistant::Text.day(record.spent_on))
      when ::Message then I18n.t("assistant.basis.forum_post", subject: record.root.subject.truncate(40), date: short_date(record.created_at))
      when MeetingAgendaItem
        I18n.t("assistant.basis.agenda_item", meeting: record.meeting.title, item: record.title.to_s.truncate(40),
                                              number: agenda_number(record),
                                              date: Assistant::Text.day(record.meeting.start_time.to_date))
      when Assistant::Conversation then I18n.t("assistant.basis.conversation")
      when Assistant::Duty then I18n.t("assistant.basis.duty", duty: I18n.t("assistant.duties.kinds.#{record.kind}.title"))
      else describe_other(record)
      end
    end

    def self.describe_other(record)
      return I18n.t("assistant.basis.pull_request", number: record.number, title: record.title.to_s.truncate(40)) if pull_request?(record)

      type = record.class.model_name.human
      title = %i[title name subject].filter_map { record.try(it).presence }.first
      title ? I18n.t("assistant.basis.record", type:, title: title.to_s.truncate(40)) : type
    end

    def self.pull_request?(record) = defined?(::GithubPullRequest) && record.is_a?(::GithubPullRequest)

    def self.describe_journal(journal)
      date = short_date(journal.created_at)
      case journal.journable
      when ::Message then I18n.t("assistant.basis.forum_post", subject: journal.journable.root.subject.truncate(40), date:)
      when ::WikiPage then I18n.t("assistant.basis.wiki_edit", title: journal.journable.title.truncate(40), date:)
      when ::News then I18n.t("assistant.basis.news", title: journal.journable.title.truncate(40), date:)
      else I18n.t("assistant.basis.comment", subject: journal.journable.try(:subject).to_s.truncate(40), date:)
      end
    end

    def self.short_date(time) = Assistant::Text.day(time.to_date)

    def self.agenda_number(item)
      ids = item.meeting.agenda_items.unscope(:order).joins(:meeting_section)
                .order("meeting_sections.position", :position).pluck(:id)
      ids.index(item.id).to_i + 1
    end

    def record = GlobalID::Locator.locate(gid)
  rescue ActiveRecord::RecordNotFound
    nil

    def to_h = { "kind" => kind, "gid" => gid, "quote" => quote, "label" => label }.compact
  end
end
