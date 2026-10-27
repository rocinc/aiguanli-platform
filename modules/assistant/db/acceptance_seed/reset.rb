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

module AssistantSeed
  class Reset
    SECOND_IDENTIFIER = "research-notes"

    def initialize(ctx)
      @ctx = ctx
    end

    def call
      User.current = @ctx.admin
      clear_assistant_state
      projects.each { clear_content(it) }
      clear_people_time
    end

    private

    def projects = Project.where(identifier: ["quill", SECOND_IDENTIFIER]).to_a

    def clear_assistant_state
      [Assistant::Signal, Assistant::Action, Assistant::Message, Assistant::Conversation, Assistant::Event,
       Assistant::Extraction, Assistant::Intent, Assistant::FollowUp, Assistant::IdeaMention, Assistant::Idea,
       Assistant::View, Assistant::Grant, Assistant::AppraisalNote, Assistant::AppraisalView, Assistant::Appraisal,
       Assistant::Usage].each(&:delete_all)
      Assistant::Duty.update_all(last_run_at: nil, last_result: {}, unseen_runs: 0)
    end

    def clear_content(project)
      Meeting.where(project:).destroy_all
      destroy_work_packages(project)
      TimeEntry.where(project_id: project.id).find_each do |entry|
        Journal.where(journable_type: "TimeEntry", journable_id: entry.id).find_each(&:destroy)
        entry.destroy
      end
      Journal.where(journable_type: "TimeEntry").where.not(journable_id: TimeEntry.select(:id)).find_each(&:destroy)
      Version.where(project_id: project.id).where.not(id: [21, 22]).destroy_all if project.identifier == "quill"
      Sprint.where(project_id: project.id, name: %w[Sprint\ 1 Sprint\ 2 Sprint\ 3]).destroy_all
      GithubPullRequest.find_each(&:destroy) if defined?(GithubPullRequest)
    end

    def destroy_work_packages(project)
      scope = WorkPackage.where(project_id: project.id)
      12.times do
        break unless scope.exists?

        parents = WorkPackage.where.not(parent_id: nil).select(:parent_id)
        scope.where.not(id: parents).find_each(&:destroy!)
      end
      raise "work packages of #{project.identifier} remain" if scope.exists?
    end

    def clear_people_time
      UserNonWorkingTime.where(user_id: PEOPLE.values).delete_all
    end
  end
end
