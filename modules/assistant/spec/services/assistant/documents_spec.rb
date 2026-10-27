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

require "spec_helper"
require_relative "../../support/intent_helpers"

# 04 D5: documents and attachments.
RSpec.describe "Reading documents", with_settings: { assistant_read_attachments: true } do # rubocop:disable RSpec/DescribeClass
  shared_let(:project) do
    create(:project, enabled_module_names: %w[work_package_tracking assistant documents])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant
                                          view_documents manage_documents])
  end
  shared_let(:lea) { create(:user, firstname: "Lea", member_with_roles: { project => role }) }
  shared_let(:outsider) { create(:user) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Export") }

  before do
    allow(Assistant::Llm).to receive(:configured?).and_return(true)
    allow(Assistant::Llm).to receive(:configured?).and_return(true)
  end

  def upload(text, at:, filename: "spec.txt")
    travel_to(at) do
      create(:attachment, container: work_package, author: lea, filename:, content_type: "text/plain").tap do
        Attachment.where(id: it.id).update_all(fulltext: text)
      end
    end
  end

  def tool(user = lea) = Assistant::Reasoning::Tools::DocumentTool.new(Assistant::Reasoning::Tools::Context.new(user:, project:))

  it "reads an attached file and tells what changed against its earlier upload" do
    upload("Export as PDF.\nPage numbers in the footer.", at: 3.days.ago)
    latest = upload("Export as PDF and CSV.\nPage numbers in the footer.", at: 1.day.ago)

    result = tool.call("attachment" => latest.id, "compare" => true)

    expect(result).to include("title" => "spec.txt", "upload" => 2)
    expect(result["changes"]).to include("added" => ["Export as PDF and CSV."], "removed" => ["Export as PDF."])
  end

  it "reads nothing someone may not open, and nothing before the administrator allowed it" do
    file = upload("Secret plan.", at: 1.day.ago)

    expect { tool(outsider).call("attachment" => file.id) }.to raise_error(Assistant::Reasoning::Tools::Refused)
    with_settings(assistant_read_attachments: false) do
      expect { tool.call("attachment" => file.id) }.to raise_error(Assistant::Reasoning::Tools::Refused, /administrator/)
    end
  end

  describe Assistant::Proactive::Detectors::DocumentConflictsDecision do
    before do
      create_intent(project:, subject: work_package, owner: lea, kind: "decision", status: "active",
                    title: "导出只支持 PDF 格式", quote: "导出先只做 PDF 格式，CSV 以后再说", stated_at: 10.days.ago)
    end

    it "asks the uploader to check a file that talks about a decided matter, quoting both" do
      upload("需求说明\n\n导出功能需要同时支持 PDF 格式和 CSV 格式，并且带页码。", at: 1.hour.ago, filename: "需求.txt")

      found = described_class.new(project).candidates.sole

      expect(found).to have_attributes(recipient: lea, certainty: :likely)
      expect(found.because.join).to include("导出先只做 PDF 格式", "同时支持 PDF 格式和 CSV 格式")
    end
  end
end
