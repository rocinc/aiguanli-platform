# frozen_string_literal: true

require_relative "support"

module DemoSeed
  ORDER = %w[Backbone Ceremony Docs TalkHistory TalkNow Git TimeCost Polish LedgerDemo].freeze

  # DEMO_ONLY=Backbone,TimeCost limits the run to the named steps (sandbox rehearsals).
  def self.steps
    only = ENV["DEMO_ONLY"].to_s.split(",").map(&:strip).compact_blank
    ORDER.filter_map do |name|
      next if only.any? && only.exclude?(name)

      file = File.expand_path("#{name.underscore}.rb", __dir__)
      next unless File.exist?(file)

      require file
      const_get(name)
    end
  end
end
