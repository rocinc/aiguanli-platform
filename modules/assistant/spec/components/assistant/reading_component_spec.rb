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

require "rails_helper"

RSpec.describe Assistant::ReadingComponent, type: :component do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages add_work_package_comments use_assistant]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:) }

  let(:journal) do
    work_package.add_journal(user: sam, notes: "I'll get the API done by Friday, @#{AssistantUser::LOGIN}")
    work_package.save_journals
    work_package.journals.where(user: sam).last
  end

  def render_for(user = sam) = render_inline(described_class.new(journal:, user:))

  it "says it is reading, and polls only itself, right after the author posts" do
    allow(Assistant::Llm).to receive(:configured?).and_return(true)
    render_for

    expect(page).to have_css("[data-assistant-reading-state='reading'][data-controller='assistant--reading']")
    expect(page).to have_css("[role='status']", text: "is reading this comment")
  end

  it "takes no room when there was nothing to note" do
    journal
    work_package.add_journal(user: Assistant.user, notes: "Noted.")
    work_package.save_journals
    render_for

    expect(page).to have_css("[data-assistant-reading-state='nothing']")
    expect(page).to have_no_css("[role='status']")
    expect(page).to have_no_css("[data-controller]")
  end

  it "says what it took from the comment, in one line" do
    journal
    work_package.add_journal(user: Assistant.user, notes: "Noted.")
    work_package.save_journals
    Assistant::Intent.create!(project:, source: journal, subject: work_package, work_package:, owner: sam, kind: "commitment",
                              status: "open", strength: "firm", title: "Finish the API", quote: "I'll get the API done by Friday",
                              stated_at: journal.created_at, said_due_on: Date.new(2030, 1, 4), extractor_version: "test")
    render_for

    expect(page).to have_css("[data-assistant-reading-state='noted'] [role='status']", text: /Finish the API/)
  end

  it "shows nothing to anyone else" do
    other = create(:user, member_with_roles: { project => role })

    expect(Assistant::Reading.new(journal:, user: other).state).to eq(:none)
  end
end
