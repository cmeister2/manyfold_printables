# frozen_string_literal: true

module ManyfoldPrintables
  class SettingsController < ::ApplicationController
    before_action { authorize :settings, :integrations? }
    protect_from_forgery with: :exception

    def update
      settings = params.permit(:enabled)
      SiteSettings.printables_enabled = settings[:enabled] == "1" if settings.key?(:enabled)
      redirect_to main_app.integrations_settings_path, notice: "Printables settings saved.", status: :see_other
    end
  end
end
