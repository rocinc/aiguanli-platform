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
  # What a person does about a notice besides choosing one of its options:
  # leave it, later, not this kind of thing, or this is wrong. Choosing an
  # option goes through the action's own buttons instead. Every answer is a
  # sentence that replaces the notice, on every page that shows it.
  class SignalsController < ApplicationController
    include OpTurbo::ComponentStream

    OUTCOMES = %w[rejected snoozed muted wrong known not_mine bad_timing].freeze

    before_action :find_signal
    authorization_checked! :update

    def update
      outcome = params[:outcome].to_s
      return head :unprocessable_entity unless OUTCOMES.include?(outcome)

      @reply = answer(outcome)

      respond_to do |format|
        format.turbo_stream { render turbo_stream: streams }
        format.html { redirect_back_or_to(my_page_path) }
      end
    end

    private

    def find_signal
      @signal = Assistant::Signal.where(recipient: current_user).find(params.expect(:id))
    end

    def controls = @controls ||= Assistant::Notice::Controls.new(@signal, current_user)

    def answer(outcome)
      case outcome
      when "rejected" then controls.leave
      when "snoozed" then controls.snooze(params[:until].presence, reason: params[:reason].presence)
      when "muted" then controls.mute(params[:scope])
      when "wrong" then controls.wrong
      when "known" then controls.known
      when "not_mine" then controls.not_mine
      when "bad_timing" then controls.timing
      end
    end

    def streams
      [*notice_streams,
       OpTurbo::StreamComponent.new(action: :liveRegion, message: @reply.sentence, politeness: "polite", delay: nil,
                                    target: nil).render_in(view_context)]
    end

    def notice_streams
      densities = @reply.step ? [clicked_density] : Assistant::NoticeComponent::DENSITIES
      densities.map do |density|
        component = Assistant::NoticeComponent.new(signal: @signal.reload, user: current_user, density:, reply: @reply.sentence,
                                                   step: @reply.step, heading_level: params[:heading_level] || 3)
        turbo_stream.replace_all(Assistant::NoticeComponent.selector(@signal, density), component)
      end
    end

    def clicked_density
      Assistant::NoticeComponent::DENSITIES.find { it.to_s == params[:density].to_s } || :card
    end
  end
end
