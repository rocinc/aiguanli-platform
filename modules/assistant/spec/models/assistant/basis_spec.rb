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

require "spec_helper"

RSpec.describe Assistant::Basis do
  it "describes a GitHub pull request by number and title, and links to its page" do
    pull_request = create(:github_pull_request, number: 22, title: "修复试用到期后仍可无限调用")

    basis = described_class.for(pull_request)

    expect(basis.label).to eq(I18n.t("assistant.basis.pull_request", number: 22, title: "修复试用到期后仍可无限调用"))
    expect(basis.label).not_to include("#<")
    expect(Assistant::Provenance.url_for_basis(basis.to_h)).to eq(pull_request.github_html_url)
  end

  it "falls back to the kind and the title for any other record" do
    version = build_stubbed(:version, name: "v2.0 团队版")

    expect(described_class.describe(version)).to eq(I18n.t("assistant.basis.record", type: Version.model_name.human, title: "v2.0 团队版"))
  end
end
