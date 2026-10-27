module Assistant
  module Admin
    class SettingsController < ::Admin::SettingsController
      menu_item :assistant_settings

      def show
        @consent = Setting.assistant_llm_consent?
        @configured = Assistant::Llm.configured?
        @key_present = Assistant::Llm.key_present?
        @usage = Assistant::Usage.this_month
        @by_purpose = @usage.group(:purpose).order(Arel.sql("SUM(prompt_tokens + completion_tokens) DESC"))
                            .pluck(:purpose, Arel.sql("COUNT(*)"), Arel.sql("SUM(prompt_tokens + completion_tokens)"),
                                   Arel.sql("SUM(CASE WHEN succeeded THEN 0 ELSE 1 END)"))
        @total = @by_purpose.sum { it[2].to_i }
        @budget = Setting.assistant_monthly_token_budget.to_i
        @projects = Project.active.has_module(:assistant).order(:name).to_a
      end

      def test_connection
        render partial: "assistant/admin/settings/connection_test", locals: { results: Assistant::LlmCheck.call },
               layout: false
      end

      private

      def success_callback(_call)
        AssistantUser.rename!(Setting.assistant_display_name.presence || I18n.t("assistant.admin.default_name"))
        flash[:notice] = t(:notice_successful_update)
        redirect_to admin_settings_assistant_path
      end

      def failure_callback(call)
        flash[:error] = call.message || I18n.t(:notice_internal_server_error)
        redirect_to admin_settings_assistant_path
      end
    end
  end
end
