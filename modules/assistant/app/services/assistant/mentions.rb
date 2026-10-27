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
  # A draft's words are edited as plain text ("@Bob Fischer") and go out with
  # real mentions, so the person written about is still told.
  module Mentions
    TAG = %r{<mention\b[^>]*>.*?</mention>}m

    module_function

    def to_text(markup)
      markup.to_s.gsub(TAG) { |tag| text_of(tag) }
    end

    # Names written with an @ become mentions again: the ones the draft had
    # keep their tag, members of the project get a new one.
    def from_text(text, original:, project:)
      tags = member_tags(project).merge(tags_in(original))
      return text if tags.empty?

      pattern = /(?<![\w@])(#{tags.keys.sort_by { -it.length }.map { Regexp.escape(it) }.join('|')})(?![\p{L}\p{N}_])/
      text.to_s.split(/(#{TAG})/).each_with_index.map do |part, index|
        index.odd? ? part : part.gsub(pattern) { tags.fetch(Regexp.last_match(1)) }
      end.join
    end

    def text_of(tag)
      CGI.unescapeHTML(tag.sub(/\A<mention\b[^>]*>/, "").delete_suffix("</mention>")).strip
    end

    def tags_in(markup) = markup.to_s.scan(TAG).to_h { [text_of(it), it] }

    def member_tags(project)
      return {} unless project

      project.principals.where(type: %w[User Group]).to_h { ["@#{it.name}", Assistant::Reasoning::StepBuilder.mention(it)] }
    end
  end
end
