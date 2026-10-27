# frozen_string_literal: true

module DemoSeed
  # Shared lookups for every demo step. Steps receive an AssistantSeed::Context and must only rely on
  # work packages by id (#42-#121 are stable) or by subject through #wp.
  module Support
    def self.included(base) = base.attr_reader(:ctx)

    def initialize(ctx) = @ctx = ctx

    def project = ctx.project

    def user(key) = ctx.user(key)

    def wp(ref)
      return WorkPackage.find(ref) if ref.is_a?(Integer)

      WorkPackage.find_by!(project:, subject: ref)
    end

    def say(message) = ctx.say("demo: #{message}")

    def as(key, &)
      previous = User.current
      User.current = key == :assistant ? AssistantUser.first : user(key)
      yield
    ensure
      User.current = previous
    end
  end
end
