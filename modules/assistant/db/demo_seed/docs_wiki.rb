# frozen_string_literal: true

module DemoSeed
  module DocsWiki
    private

    def wiki
      @pages = {}
      decision_details
      risk_register
      retrospectives
      glossary
      velocity_baseline
      test_strategy
      user_journeys
      meeting_archive
      tech_debt
      refinement_rules
      release_notes_draft
      v2_scope
      link_decision_index
      say("wiki pages=#{@pages.size}")
    end

    # versions: [[day, "HH:MM", author, text, edit_note], ...]; every entry becomes one journal.
    def write_page(title, versions, parent: nil)
      page = nil
      stamps = []
      versions.each do |day, hm, key, text, note|
        as(key) do
          if page
            page.text = fmt(text)
            page.journal_notes = note
          else
            page = WikiPage.new(wiki: project.wiki, title:, parent:, author: user(key), text: fmt(text))
          end
          page.save!
        end
        stamps << t(day, hm)
      end
      restamp(page, stamps)
      @pages[title] = page
    end

    def link_decision_index
      index = project.wiki.pages.find_by!(title: "决定记录")
      return if index.text.include?("决定记录：详述")

      as(:sam) do
        index.text = "#{index.text.rstrip}\n\n每一条决定的背景、选项、结论和当时的原话，见 [[决定记录：详述]]。\n"
        index.journal_notes = "加上详述页的入口"
        index.save!
      end
      stamp = t(-3, "10:30")
      journals = Journal.where(journable_type: "WikiPage", journable_id: index.id).order(:version).to_a
      journals.last.update_columns(created_at: stamp, updated_at: stamp, validity_period: (stamp...nil))
      earlier = journals[-2]
      earlier&.update_columns(validity_period: (earlier.created_at...stamp))
      index.update_columns(updated_at: stamp)
    end
  end
end
