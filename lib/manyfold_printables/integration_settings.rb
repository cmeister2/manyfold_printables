# frozen_string_literal: true

module ManyfoldPrintables
  # Append our own form without replacing the host's settings template or
  # sending a partial provider configuration to its shared update action.
  module IntegrationSettings
    def self.install!
      ActionView::Template.prepend(TemplateSection) unless ActionView::Template < TemplateSection
    end

    module TemplateSection
      def render(view, locals, *arguments, **options, &block)
        content = super
        return content unless virtual_path == "settings/integrations"

        view.safe_join([content, view.render("manyfold_printables/settings/integration")])
      end
    end
  end
end
