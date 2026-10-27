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


require "spec_helper"

RSpec.describe Assistant::Proactive::Detectors::IdeaGarden do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages add_work_package_comments]) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:) }

  def comment(notes)
    work_package.add_journal(user: ben, notes:)
    work_package.save!(validate: false)
  end

  def harvested
    described_class.new(project, today: Date.current, since: 1.day.ago).candidates
    Assistant::Idea.where(project:).pluck(:title)
  end

  it "keeps the sentences that wish for something" do
    comment("要是能按段落指纹定位就好了")
    comment("以后可以考虑把导出做成异步任务")
    comment("能不能支持按版本筛选决定记录？")

    expect(harvested).to contain_exactly("按段落指纹定位", "把导出做成异步任务", "支持按版本筛选决定记录")
  end

  it "leaves out a request made to someone" do
    comment("能不能请 Bob 周二前把 #73 的接口说明单独发给我？")
    comment("可不可以给我一份接口草稿？")
    comment("请帮我看一下，能不能今天合并？")

    expect(harvested).to be_empty
  end
end
