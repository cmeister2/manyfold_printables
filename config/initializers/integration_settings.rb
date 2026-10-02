# frozen_string_literal: true

Rails.application.config.to_prepare do
  unless SiteSettings.keys.include?("printables_enabled")
    SiteSettings.field :printables_enabled, type: :boolean, default: true
  end
end
