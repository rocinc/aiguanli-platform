# frozen_string_literal: true

class CleanupOtherDocumentType < ActiveRecord::Migration[8.0]
  def change
    reversible do |dir|
      dir.up do
        cleanup_other_document_type_if_orphaned
      end

      # No-op for down migration
    end
  end

  private

  def cleanup_other_document_type_if_orphaned
    say_with_time "Cleaning up orphaned 'Other' document type" do
      names = ["Other"]
      localised_name = localised_other_name
      names << localised_name if localised_name.present?
      placeholders = names.map { "?" }.join(", ")

      sql = <<~SQL.squish
        DELETE FROM document_types
        WHERE name IN (#{placeholders})
        AND NOT EXISTS (
          SELECT 1
          FROM documents
          WHERE documents.type_id = document_types.id
        )
      SQL

      execute OpenProject::SqlSanitization.sanitize(sql, *names)
    end
  end

  def localised_other_name
    return if Setting.default_language == "en"

    I18n.t!("seeds.common.document_categories.item_2.name", locale: Setting.default_language)
  rescue I18n::MissingTranslationData
    nil
  end
end
