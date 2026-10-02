# frozen_string_literal: true

module ManyfoldPrintables
  # Preserve the creator card and its native actions on hosts without the hook.
  module CreatorMenu
    CONTEXT = :@manyfold_printables_creator_menu
    COOPERATIVE_HOOK = true

    def self.install!
      ActionView::Template.prepend(TemplateContext) unless ActionView::Template < TemplateContext
      ComponentsHelper.prepend(MenuItems) unless ComponentsHelper < MenuItems
    end

    # Older shims render every provider; defer to those, while shims that always
    # defer to another provider leave this one active. Cooperating copies choose
    # one renderer, regardless of plugin initialization order.
    def self.external_hook?
      helpers = ComponentsHelper.ancestors.filter_map do |helper|
        name = helper.name
        next if helper == MenuItems || !name&.end_with?("::CreatorMenu::MenuItems")

        template_name = name.delete_suffix("::MenuItems") + "::TemplateContext"
        next unless ActionView::Template.ancestors.any? { |template| template.name == template_name }

        [helper, Object.const_get(name.delete_suffix("::MenuItems"))]
      end
      return true if helpers.any? { |_, provider| !provider.respond_to?(:external_hook?) }

      cooperating = helpers.filter_map do |helper, provider|
        helper if provider.const_defined?(:COOPERATIVE_HOOK, false) && provider.const_get(:COOPERATIVE_HOOK, false)
      end
      [MenuItems, *cooperating].min_by(&:name) != MenuItems
    end

    module TemplateContext
      def render(view, locals, *arguments, **options, &block)
        return super if CreatorMenu.external_hook?

        previous = view.instance_variable_get(CONTEXT)
        creator = if virtual_path == "creators/_creator" &&
            !source.match?(/components_for\s*(?:\(\s*)?:creator_menu\b/)
          locals[:creator]
        end
        view.instance_variable_set(CONTEXT, creator)
        begin
          super
        ensure
          view.instance_variable_set(CONTEXT, previous)
        end
      end
    end

    module MenuItems
      def BurgerMenu(**arguments, &block)
        return super if CreatorMenu.external_hook?

        creator = instance_variable_get(CONTEXT)
        components = PluginManager.components_for(:creator_menu)
        return super unless creator && block && components.any?

        super(**arguments) do |*block_arguments|
          original_items = capture(*block_arguments, &block)
          additional_items = components.filter_map do |component|
            content = render(component.new(creator: creator))
            content_tag(:li, content, role: "presentation") if content.present?
          end
          safe_join([original_items, *additional_items])
        end
      end
    end
  end
end
