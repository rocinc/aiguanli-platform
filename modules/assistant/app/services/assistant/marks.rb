# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  # The decisions that bear on an object, as one reader may see them (S5.1):
  # those made about the object itself, then those whose words overlap its
  # own. A decision whose original words the reader cannot open is left out
  # altogether rather than shown without them.
  class Marks
    LIMIT = 3
    TEXT_LIMIT = 1500

    Mark = Data.define(:decision, :day, :where, :speaker, :person, :url)

    def self.for(object, user) = new(object, user).marks

    def self.visible_source?(source, user)
      case source
      when Journal then source.journable.present? && source.visible?(user)
      when MeetingAgendaItem then source.meeting.visible?(user)
      else source.respond_to?(:visible?) && source.visible?(user)
      end
    end

    def initialize(object, user)
      @object = object
      @user = user
    end

    attr_reader :object, :user

    def marks
      @marks ||= applicable? ? candidates.filter_map { build(it) }.first(LIMIT) : []
    end

    private

    def applicable?
      project.present? && user&.logged? && Assistant::Surface.available?(project, user) &&
        (object.is_a?(WorkPackage) || object.is_a?(Version) || (object.is_a?(WikiPage) && !decision_record?))
    end

    def project = @project ||= object.try(:project)

    def decision_record? = object.title == Assistant::DecisionRecord.title(project)

    def candidates
      said = Assistant::Said.new(user)
      about = said.on_subject(object).where(kind: "decision", status: "active").reorder(stated_at: :desc).to_a
      related = said.related_decisions(project, text).to_a
      (about + related).uniq.sort_by.with_index { |decision, index| [about.include?(decision) ? 0 : 1, index] }
    end

    def text
      case object
      when WorkPackage then "#{object.subject} #{Assistant::Text.plain(object.description).first(TEXT_LIMIT)}"
      when Version then "#{object.name} #{object.description}"
      else "#{object.title} #{object.text.to_s.first(TEXT_LIMIT)}"
      end
    end

    def build(decision)
      source = decision.source
      return unless source && visible?(source)

      Mark.new(decision:, day: Assistant::Text.day(decision.stated_at.to_date), where: where(source),
               speaker: decision.owner&.name, person: decision.owner, url: Assistant::Provenance.url_for_basis(Assistant::Basis.for(source).to_h))
    end

    def visible?(source) = self.class.visible_source?(source, user)

    def where(source)
      case source
      when Journal
        journable = source.journable
        return if journable == object

        journable.is_a?(WorkPackage) ? I18n.t("assistant.marks.where.work_package", id: journable.id) : Assistant::Basis.describe(source)
      when MeetingAgendaItem then source.meeting.title.truncate(30)
      when ::Message then I18n.t("assistant.marks.where.forum")
      else Assistant::Basis.describe(source)
      end
    end
  end
end
