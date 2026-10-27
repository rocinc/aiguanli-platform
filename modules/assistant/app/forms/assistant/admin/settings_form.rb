module Assistant
  module Admin
    class SettingsForm < ApplicationForm
      include ::Settings::FormHelper

      settings_form do |sf|
        sf.check_box(name: :assistant_llm_consent,
                     label: I18n.t("assistant.admin.consent_label"),
                     caption: I18n.t("assistant.admin.consent_caption"))
        sf.text_field(name: :assistant_llm_base_url,
                      label: I18n.t("assistant.admin.base_url_label"),
                      caption: I18n.t("assistant.admin.base_url_caption"),
                      input_width: :large)
        sf.text_field(name: :assistant_llm_name,
                      label: I18n.t("assistant.admin.llm_name_label"),
                      caption: I18n.t("assistant.admin.llm_name_caption"),
                      input_width: :medium)
        sf.text_field(name: :assistant_display_name,
                      label: I18n.t("assistant.admin.display_name_label"),
                      caption: I18n.t("assistant.admin.display_name_caption",
                                      default_name: I18n.t("assistant.admin.default_name")),
                      input_width: :medium)
        sf.text_field(name: :assistant_reasoning_model,
                      label: I18n.t("assistant.admin.model_label"),
                      caption: I18n.t("assistant.admin.model_caption"),
                      input_width: :medium)
        sf.text_field(name: :assistant_monthly_token_budget,
                      type: :number,
                      label: I18n.t("assistant.admin.budget_label"),
                      caption: I18n.t("assistant.admin.budget_caption"),
                      input_width: :small)
        sf.select_list(name: :assistant_default_proactivity,
                       label: I18n.t("assistant.admin.proactivity_label"),
                       caption: I18n.t("assistant.admin.proactivity_caption"),
                       values: Assistant::Preference::LEVELS.map do |level|
                         [I18n.t("assistant.admin.proactivity.#{level}"), level]
                       end)
        sf.check_box(name: :assistant_read_attachments,
                     label: I18n.t("assistant.admin.read_attachments_label"),
                     caption: I18n.t("assistant.admin.read_attachments_caption"))
      end
    end
  end
end
