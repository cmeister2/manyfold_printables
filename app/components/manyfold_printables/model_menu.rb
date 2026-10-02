# frozen_string_literal: true

module Components::ManyfoldPrintables
  class ModelMenu < Components::Base
    def initialize(model:)
      @model = model
    end

    def view_template
      return unless ::ManyfoldPrintables::ApiClient.configured?
      return unless current_user && policy(:settings).integrations? && policy(@model).sync?

      a(href: view_context.manyfold_printables.link_path(model_id: @model.to_param),
        class: "dropdown-item", role: "menuitem", rel: "nofollow") do
        Icon(icon: "link-45deg", label: "Link to Printables")
        whitespace
        span { "Link to Printables" }
      end
    end
  end
end
