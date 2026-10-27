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
  # The brief as the daily mail reads it: the same groups as the widget, one
  # line each, with a link to where it is handled. Built when the mail is
  # rendered, so the words come out in the reader's language.
  class BriefDigest
    Line = Data.define(:project, :text, :detail, :url)

    GROUPS = %i[away decisions drafts done].freeze

    def initialize(brief)
      @brief = brief
      @user = brief.user
    end

    attr_reader :brief

    delegate :deferred, to: :brief

    def deferred_count = deferred.size

    def sections = GROUPS.filter_map { |key| [key, send(key)] if send(key).any? }


    def any? = sections.any?

    def away
      return [] unless brief.away

      %w[asked reassigned changed promised].flat_map { Array(brief.away[it]) }.map do |item|
        Line.new(project: (item.dig("subject", "project") if brief.multiple_projects?), text: item["headline"],
                 detail: Array(item["because"]).first, url: item.dig("subject", "url") && absolute(item.dig("subject", "url")))
      end
    end

    def decisions
      brief.decisions.map do |signal|
        Line.new(project: project_of(signal), text: signal.headline, detail: signal.because.first,
                 url: subject_url(signal) || page_url)
      end
    end

    def drafts
      brief.drafts.map do |item|
        action = item.action
        target = Assistant::Drafts::Target.for(action.steps.first, @user)
        text = I18n.t("assistant.draft.leads.#{action.steps.first['op']}", target: target.label)
        Line.new(project: project_of(action), text:, detail: nil, url: page_url)
      end
    end

    def done
      brief.done.map do |action|
        sentence = Assistant::Receipts::Sentence.new(action, user: @user).call
        Line.new(project: project_of(action), text: sentence.text.sub(Assistant::Receipts::Sentence::MARK, sentence.label.to_s),
                 detail: nil, url: sentence.url && absolute(sentence.url))
      end
    end

    private

    def project_of(record) = (record.project&.name if brief.multiple_projects?)

    def subject_url(signal)
      path = case (subject = signal.subject)
             when WorkPackage then helpers.work_package_path(subject)
             when Project then helpers.project_path(subject)
             when ::Meeting then helpers.meeting_path(subject)
             end
      path && absolute(path)
    end

    def page_url = helpers.my_page_url

    def absolute(path) = path.start_with?("http") ? path : "#{Setting.protocol}://#{Setting.host_name}#{path}"

    def helpers = @helpers ||= OpenProject::StaticRouting::StaticUrlHelpers.new
  end
end
