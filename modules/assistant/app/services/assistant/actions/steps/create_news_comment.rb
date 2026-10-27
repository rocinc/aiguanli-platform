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
      # A comment under a news item, in the assistant's own name. The host
      # has no service for news comments; its controller saves them directly,
      # so this checks the same permission the controller does.
      class CreateNewsComment < Base
        def project = news&.project

        def news = @news ||= ::News.find_by(id: attributes["news_id"])

        def call(user:, cause:)
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless news
          return Outcome.failure(I18n.t("assistant.actions.errors.not_allowed")) unless user.allowed_in_project?(:comment_news, project)

          comment = news.comments.build(author: user, comments: attributes["comments"].to_s)
          return Outcome.failure(Steps.sentences(comment.errors)) unless comment.save

          Outcome.new(success: true, errors: [], touches: [Touch.new(record: comment, changes: {}, created: true)])
        end
      end
    end
  end
end
