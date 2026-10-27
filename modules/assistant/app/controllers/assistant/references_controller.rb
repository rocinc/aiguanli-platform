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
  # What the panel's input offers after an @ or a #: work packages, people
  # and versions the person may see, in the project they are looking at.
  class ReferencesController < ApplicationController
    include Assistant::ContextLookup

    LIMIT = 6

    before_action :require_login
    authorization_checked! :index

    def index
      project = project_of(locate_context(params[:context]))
      return render(json: []) unless allowed_in?(project)

      render json: references(project, params[:q].to_s.strip.first(60), params[:trigger] == "@")
    end

    private

    def references(project, term, with_people)
      found = []
      found.concat(people(project, term)) if with_people && project
      found.concat(work_packages(project, term))
      found.concat(versions(project, term)) if with_people && project
      found.first(LIMIT)
    end

    def people(project, term)
      scope = User.visible(current_user).where(id: project.users.select(:id))
      scope = scope.like(term) if term.present?
      scope.order(:lastname, :firstname).limit(LIMIT).map { { kind: "user", label: it.name, text: "@#{it.name}" } }
    end

    def work_packages(project, term)
      scope = WorkPackage.visible(current_user)
      scope = scope.where(project:) if project
      scope = matching(scope, term)
      scope.reorder(updated_at: :desc).limit(LIMIT).map do
        { kind: "work_package", label: "##{it.id} #{it.subject.truncate(60)}", text: "##{it.id}" }
      end
    end

    def matching(scope, term)
      return scope if term.blank?

      like = "%#{WorkPackage.sanitize_sql_like(term)}%"
      by_subject = scope.where("subject ILIKE ?", like)
      term.match?(/\A\d+\z/) ? scope.where(id: term.to_i).or(by_subject) : by_subject
    end

    def versions(project, term)
      scope = project.shared_versions.visible(current_user)
      scope = scope.where("versions.name ILIKE ?", "%#{Version.sanitize_sql_like(term)}%") if term.present?
      scope.limit(2).map do
        { kind: "version", label: I18n.t("assistant.panel.references.version", name: it.name), text: it.name }
      end
    end
  end
end
