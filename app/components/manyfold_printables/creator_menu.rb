# frozen_string_literal: true

module Components::ManyfoldPrintables
  class CreatorMenu < Components::Base
    register_value_helper :policy_scope

    def initialize(creator:)
      @creator = creator
    end

    def view_template
      return unless ::ManyfoldPrintables::ApiClient.configured?
      return unless current_user && policy(:settings).integrations? && policy(@creator).sync?
      return if ::ManyfoldPrintables::CreatorSource.linked?(@creator)
      return unless ::ManyfoldPrintables::CreatorModels.linked?(@creator, models: policy_scope(::Model))

      a(href: view_context.manyfold_printables.creator_link_path(creator_id: @creator.to_param),
        class: "dropdown-item", role: "menuitem", rel: "nofollow") do
        Icon(icon: "link-45deg", label: "Link to Printables")
        whitespace
        span { "Link to Printables" }
      end
    end
  end
end
