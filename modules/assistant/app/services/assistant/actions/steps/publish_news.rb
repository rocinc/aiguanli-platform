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
  module Actions
    module Steps
      # Publishes a news item the assistant drafted (04 D3): release notes, a
      # phase reached. It is public and is not taken back, so it is always T3
      # and goes out in the name of the person who confirmed it.
      class PublishNews < Base
        def self.in_deciders_name? = true

        def project = Project.find_by(id: attributes["project_id"])

        def call(user:, cause:) # rubocop:disable Lint/UnusedMethodArgument
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless project

          call = ::News::CreateService.new(user:).call(project:, title: attributes["title"].to_s.truncate(255),
                                                       summary: attributes["summary"], description: attributes["description"])
          call.success? ? outcome_from(call) : Outcome.failure(errors_of(call))
        end
      end
    end
  end
end
