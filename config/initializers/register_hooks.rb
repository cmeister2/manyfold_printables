# frozen_string_literal: true

Rails.application.config.after_initialize do
  require "manyfold/provider_menu"
  Manyfold::ProviderMenu.register(Components::ManyfoldPrintables::ProviderMenuItem)
  PluginManager.register(:model_menu, Components::ManyfoldPrintables::ModelMenu)
  PluginManager.register(:creator_menu, Components::ManyfoldPrintables::CreatorMenu)
end

Rails.application.config.to_prepare do
  require "manyfold_printables/creator_menu"
  require "manyfold_printables/creator_links"
  require "manyfold_printables/integration_settings"
  ManyfoldPrintables::CreatorMenu.install!
  ManyfoldPrintables::CreatorLinks.install!
  ManyfoldPrintables::IntegrationSettings.install!
end
