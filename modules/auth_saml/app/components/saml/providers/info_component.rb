# frozen_string_literal: true

module Saml
  module Providers
    class InfoComponent < ApplicationComponent
      alias_method :provider, :model
    end
  end
end
