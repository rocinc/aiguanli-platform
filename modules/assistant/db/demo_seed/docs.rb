# frozen_string_literal: true

require_relative "support"
require_relative "docs_wiki"
require_relative "docs_wiki_adr"
require_relative "docs_wiki_pages"
require_relative "docs_forum"
require_relative "docs_forum_topics"
require_relative "docs_news"
require_relative "docs_documents"

module DemoSeed
  # Wiki, forum, news and documents for the Scrum demo (see 演示世界设定书 §3-§5). Everything is dated relative to the
  # seed context and written by team members who have joined by then.
  class Docs
    include Support
    include DocsWiki
    include DocsWikiAdr
    include DocsWikiPages
    include DocsForum
    include DocsForumTopics
    include DocsNews
    include DocsDocuments

    PEOPLE_TOKENS = %i[ada sam frank bob ben fiona mia quinn].freeze
    REF = %r{(?:document:"[^"]+"|(?:message|meeting|version)?\#\d+)}

    def call
      forum
      news
      wiki
      documents
    end

    private

    def t(day, hm)
      stamp = ctx.at(day.is_a?(Integer) ? day : fixed(day), hm)
      [stamp, ctx.now].min
    end

    def fixed(month_day) = Date.new(ctx.today.year, *month_day)

    def label(day) = ctx.day_label(day.is_a?(Integer) ? ctx.backward(ctx.d(day)) : fixed(day))

    def mention(key)
      person = user(key)
      %(<mention class="mention" data-id="#{person.id}" data-type="user" data-text="@#{person.name}">@#{person.name}</mention>)
    end

    def message_id(subject) = (@message_ids ||= {})[subject]

    def remember_message(subject, id) = (@message_ids ||= {})[subject] = id

    def meeting_ref(title)
      id = Meeting.where(project:, title:).pick(:id)
      id ? "meeting##{id}" : title
    end

    def version_ref(name)
      id = Version.where(project_id: project.id, name:).pick(:id)
      id ? "version##{id}" : name
    end

    def adr_number(key) = DocsWikiAdr::ADR_DEFS.index { _1[:key] == key } + 1

    def document_ref(title) = %(document:"#{title}")

    # Expands {ada}, {d:-5}, {d:[9,13]}, {m:subject}, {mt:title}, {v:name}, {doc:title} and puts a space around
    # references that the text formatter only links when separated from CJK text.
    def fmt(text)
      out = text.gsub(/\{(#{PEOPLE_TOKENS.join('|')})\}/) { mention(::Regexp.last_match(1).to_sym) }
      out = out.gsub(/\{d:(-?\d+)\}/) { label(::Regexp.last_match(1).to_i) }
      out = out.gsub(/\{d:\[(\d+),(\d+)\]\}/) { label([::Regexp.last_match(1).to_i, ::Regexp.last_match(2).to_i]) }
      out = out.gsub(/\{m:([^}]+)\}/) { message_id(::Regexp.last_match(1)) ? "message##{message_id(::Regexp.last_match(1))}" : ::Regexp.last_match(1) }
      out = out.gsub(/\{mt:([^}]+)\}/) { meeting_ref(::Regexp.last_match(1)) }
      out = out.gsub(/\{v:([^}]+)\}/) { version_ref(::Regexp.last_match(1)) }
      out = out.gsub(/\{adr:(\w+)\}/) { format("ADR-%03d", adr_number(::Regexp.last_match(1).to_sym)) }
      out = out.gsub(/\{doc:([^}]+)\}/) { document_ref(::Regexp.last_match(1)) }
      spaced(out)
    end

    def spaced(text)
      text.gsub(/(^|.)(#{REF})(?!\d)(?=(.?))/m) do
        pre = ::Regexp.last_match(1)
        ref = ::Regexp.last_match(2)
        post = ::Regexp.last_match(3)
        lead = pre.empty? || pre.match?(/[[:space:](,~\->\[|]/) ? "" : " "
        tail = post.empty? || post.match?(/[[:space:],)\]<|]/) ? "" : " "
        "#{pre}#{lead}#{ref}#{tail}"
      end
    end

    def restamp(record, requested)
      stamps = requested.each_with_object([]) { |stamp, list| list << (list.last && stamp <= list.last ? list.last + 1.minute : stamp) }
      journals = Journal.where(journable_type: record.class.base_class.name, journable_id: record.id).order(:version).to_a
      journals.each_with_index do |journal, index|
        stamp = stamps[index] || stamps.last
        journal.update_columns(created_at: stamp, updated_at: stamp, validity_period: (stamp...stamps[index + 1]))
        Assistant::Event.where(journal_id: journal.id).update_all(created_at: stamp)
      end
      record.update_columns(created_at: stamps.first, updated_at: stamps.last)
    end
  end
end
