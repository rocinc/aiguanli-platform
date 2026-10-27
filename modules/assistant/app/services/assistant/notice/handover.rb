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
  module Notice
    # After a person takes back something the assistant did on a grant, it
    # asks once whether that kind of thing should wait for them from now on
    # (L5). Answering yes takes the grant back, which makes it a T2 again.
    class Handover
      def initialize(action, user)
        @action = action
        @user = user
      end

      def grant
        @grant ||= action.project && Assistant::Grant.live.find_by(project: action.project, action_kind: action.kind)
      end

      def ask? = action.tier == "t1" && (grant_ask? || own_ask?)

      def ask!
        return false unless ask?

        if grant_ask?
          grant.update!(scope: grant.scope.merge("asked" => Array(grant.scope["asked"]) | [user.id]))
        else
          preference.asked_first!(action.kind)
        end
        true
      end

      def answer(yes)
        if grant
          grant.revoke! if yes && decider?
        elsif yes && own?
          preference.ask_first!(action.kind)
        end
        I18n.t("assistant.notice.handover.#{yes ? 'yes' : 'no'}")
      end

      private

      attr_reader :action, :user

      def decider? = user.allowed_in_project?(:manage_assistant, action.project)

      def grant_ask? = grant.present? && decider? && Array(grant.scope["asked"]).exclude?(user.id)

      # What the assistant did on its own for this person, with no team grant behind it.
      def own? = grant.nil? && action.on_behalf_of_id == user.id && action.decided_by_id.nil?

      def own_ask? = own? && !preference.asks_first?(action.kind) && !preference.asked_first?(action.kind)

      def preference = @preference ||= Assistant::Preference.for(user)
    end
  end
end
