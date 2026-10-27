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

require_relative "../spec_helper"

RSpec.describe HourlyRatesController do
  shared_let(:admin) { create(:admin) }

  let(:user) { create(:user, member_with_permissions: { project => permissions }) }
  let(:permissions) { [:view_hourly_rates] }
  let(:project) { create(:project) }
  let(:default_rate) { create(:default_hourly_rate, user:) }

  describe "#show" do
    before do
      login_as(user)
    end

    context "when accessing the hourly rates of a user with a non exisiting project" do
      it "responds with 404" do
        get :show, params: { project_id: "this-does-not-exist", id: user.id }
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when accessing the hourly rates of a user without being a member of the project" do
      let(:user) { create(:user) }

      it "responds with 404" do
        get :show, params: { project_id: project.id, id: user.id }
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when accessing the hourly rates of a user being a member of the project without permission to view hourly rates" do
      let(:permissions) { [] }

      it "responds with 403" do
        get :show, params: { project_id: project.id, id: user.id }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when accessing the hourly rates of a user with permission to view hourly rates in the project" do
      it "responds with 200" do
        get :show, params: { project_id: project.id, id: user.id }
        expect(response).to have_http_status(:ok)
      end
    end

    context "when accessing the hourly rates of a user that is not visible to me" do
      let(:other_user) { create(:user) }

      it "responds with 404" do
        get :show, params: { project_id: project.id, id: other_user.id }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "#update" do
    describe "when trying to update with an invalid rate value" do
      let(:params) do
        {
          id: user.id,
          user: { "existing_rate_attributes" => { default_rate.id.to_s => { "valid_from" => default_rate.valid_from.to_s,
                                                                            "rate" => "2d5" } } }
        }
      end

      before do
        as_logged_in_user admin do
          post :update, params:
        end
      end

      it "renders the edit template" do
        expect(response).to render_template("edit")
      end

      it "displays an error message" do
        actual_message = assigns(:user).default_rates.first.errors.messages[:rate].first
        expect(actual_message).to eq(I18n.t("activerecord.errors.messages.not_a_number"))
      end
    end

    context "when the user does not have the permission to edit hourly rates" do
      let(:user) { create(:user, member_with_permissions: { project => [:view_hourly_rates] }) }
      let(:params) do
        {
          id: user.id,
          project_id: project.id,
          user: {
            "existing_rate_attributes" => {
              default_rate.id.to_s => {
                "valid_from" => default_rate.valid_from.to_s,
                "rate" => "25"
              }
            }
          }
        }
      end

      before do
        as_logged_in_user(user) do
          post :update, params:
        end
      end

      it "responds with 403 Forbidden" do
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when trying to update the rate of a user that is not a member of the project" do
      let(:other_user) { create(:user) }
      let(:params) do
        {
          id: other_user.id,
          project_id: project.id,
          user: {
            "existing_rate_attributes" => {
              default_rate.id.to_s => {
                "valid_from" => default_rate.valid_from.to_s,
                "rate" => "25"
              }
            }
          }
        }
      end

      before do
        as_logged_in_user(admin) do
          post :update, params:
        end
      end

      it "responds with 404 Not Found" do
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when updating and adding a new rate" do
      let!(:default_rate) { create(:default_hourly_rate, user:, valid_from: 1.month.ago) }
      let!(:hourly_rate) { create(:hourly_rate, user:, project:, valid_from: 1.day.ago) }

      let(:params) do
        {
          id: user.id,
          project_id: project.id,
          user: {
            "existing_rate_attributes" => {
              hourly_rate.id.to_s => {
                "valid_from" => 2.days.ago.to_s,
                "rate" => "25"
              }
            },
            "new_rate_attributes" => {
              "0" => {
                "valid_from" => 1.day.from_now.to_s,
                "rate" => "30"
              }
            }
          }
        }
      end

      it "updates the existing rate and creates a new one" do
        # testing before state

        expect(HourlyRate.at_date_for_user_in_project(3.days.ago, user, project)).to eq(default_rate)
        expect(HourlyRate.at_date_for_user_in_project(2.days.ago, user, project)).to eq(default_rate)
        expect(HourlyRate.at_date_for_user_in_project(1.day.ago, user, project)).to eq(hourly_rate)
        expect(HourlyRate.at_date_for_user_in_project(1.day.from_now, user, project)).to eq(hourly_rate)

        login_as (admin)

        expect do
          post :update, params: params
        end.to change { user.rates.reload.size }.from(1).to(2)

        newest_rate = user.rates.last

        expect(HourlyRate.at_date_for_user_in_project(3.days.ago, user, project)).to eq(default_rate)
        expect(HourlyRate.at_date_for_user_in_project(2.days.ago, user, project)).to eq(hourly_rate)
        expect(HourlyRate.at_date_for_user_in_project(1.day.ago, user, project)).to eq(hourly_rate)
        expect(HourlyRate.at_date_for_user_in_project(1.day.from_now, user, project)).to eq(newest_rate)
      end
    end

    context "when deleting all rates of a user" do
      let!(:hourly_rate) { create(:hourly_rate, user:, project:) }

      let(:params) do
        {
          id: user.id,
          project_id: project.id
        }
      end

      it "deletes all rates of the user for the project" do
        login_as (admin)

        expect do
          post :update, params: params
        end.to change { user.rates.reload.size }.from(1).to(0)

        expect(user.rates.where(project:)).to be_empty
      end

      context "with rates in other projects" do
        let(:other_project) { create(:project) }
        let!(:other_rate) { create(:hourly_rate, user:, project: other_project) }

        it "only deletes the rates for the specified project" do
          login_as (admin)

          post :update, params: params

          expect(user.rates.where(project:)).to be_empty
          expect(user.rates.where(project: other_project)).not_to be_empty
        end
      end
    end
  end
end
