# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = "openproject-assistant"
  s.version     = "1.0.0"
  s.authors     = "OpenProject GmbH"
  s.email       = "info@openproject.com"
  s.summary     = "OpenProject AI assistant"
  s.description = "An AI team member that reads the project, reasons about it and changes it through the " \
                  "platform's own services, with every change signed, explained and undoable."
  s.license     = "GPLv3"

  s.files = Dir["{app,config,db,lib}/**/*"]
  s.metadata["rubygems_mfa_required"] = "true"
end
