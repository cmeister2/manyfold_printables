# frozen_string_literal: true

module Components::ManyfoldPrintables
  class ProviderMenuItem < Components::Base
    def self.label
      "Printables"
    end

    def view_template
      DropdownItem(label: self.class.label, icon: "box-seam", path: view_context.manyfold_printables.root_path)
    end
  end
end
