# frozen_string_literal: true

module ManyfoldPrintables
  # Extend the host's integration form before its shared submit button.
  module IntegrationSettings
    CONTEXT = :@manyfold_printables_integration_settings

    def self.install!
      ActionView::Template.prepend(TemplateSection) unless ActionView::Template < TemplateSection
      unless ::SettingsController < SettingsUpdate
        ::SettingsController.prepend(SettingsUpdate)
        ::SettingsController.prepend_before_action :verify_printables_settings_authenticity, only: :update
      end
    end

    module TemplateSection
      def render(view, locals, *arguments, **options, &block)
        if virtual_path == "settings/integrations"
          previous = view.instance_variable_get(CONTEXT)
          view.instance_variable_set(CONTEXT, true)
          begin
            super
          ensure
            view.instance_variable_set(CONTEXT, previous)
          end
        elsif virtual_path == "settings/_submit" && view.instance_variable_get(CONTEXT) && locals[:form]
          view.safe_join([view.render("manyfold_printables/settings/integration", form: locals[:form]), super])
        else
          super
        end
      end
    end

    module SettingsUpdate
      private

      # The host only checks CSRF for API requests; retain protection for this form.
      def verify_printables_settings_authenticity
        return unless params[:integrations]&.key?(:printables_enabled)

        raise ActionController::InvalidAuthenticityToken unless verified_request?
      end

      def update_integrations_settings(settings)
        super
        return unless settings&.key?(:printables_enabled)

        SiteSettings.printables_enabled = settings[:printables_enabled] == "1"
      end
    end
  end
end
