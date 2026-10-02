# frozen_string_literal: true

require "open3"

module ProviderMenuTestFixtures
  class Alpha < Components::Base
    def self.label
      "Alpha <example> & provider"
    end

    def view_template
      DropdownItem(label: self.class.label, icon: "globe", path: view_context.dashboard_path)
    end
  end

  class Zulu < Components::Base
    def self.label
      "Zulu provider"
    end

    def view_template
      DropdownItem(label: self.class.label, icon: "star", path: view_context.models_path)
    end
  end

  class AdministratorOnly < Alpha
    def self.visible?(context)
      context.current_user.has_role?(:administrator)
    end
  end

  class Hidden < Alpha
    def self.visible?(_context)
      false
    end

    def view_template
      raise "Hidden providers must not render."
    end
  end
end

class PrintablesPluginTest
  def test_provider_menu_registers_once_and_renders_sorted_native_items
    with_provider_menu_hooks do |originals|
      [ProviderMenuTestFixtures::Zulu, ProviderMenuTestFixtures::Alpha].each do |provider|
        2.times { Manyfold::ProviderMenu.register(provider) }
      end
      assert_equal 1, PluginManager.components_for(:navbar).count(Manyfold::ProviderMenu::Dropdown)
      originals.fetch(:navbar).each { |component| assert_includes PluginManager.components_for(:navbar), component }
      originals.fetch(:provider_menu).each { |component| assert_includes PluginManager.components_for(:provider_menu), component }
      assert_equal 1, PluginManager.components_for(:provider_menu).count(ProviderMenuTestFixtures::Alpha)
      assert_equal 1, PluginManager.components_for(:provider_menu).count(ProviderMenuTestFixtures::Zulu)

      session = browser(@users.first)
      session.get("/models", env: {"SCRIPT_NAME" => "/manyfold"})
      assert_equal 200, session.response.status
      document = Nokogiri::HTML(session.response.body)
      assert_equal 1, document.css("#nav-link-providers").size
      items = document.css("#providers-menu a.dropdown-item")
      assert_equal [ProviderMenuTestFixtures::Alpha.label, "Printables", ProviderMenuTestFixtures::Zulu.label],
        items.map { |item| item.text.strip }
      assert_equal "/manyfold/dashboard", items.first["href"]
      assert_equal "/manyfold/models", items.last["href"]
      refute_nil items.first.at_css(".bi-globe")
      refute_nil items.last.at_css(".bi-star")
      assert_empty document.css("#providers-menu example")
      assert_includes session.response.body, "Alpha &lt;example&gt; &amp; provider"
      assert items.all? { |item| item["role"] == "menuitem" && item.parent.name == "li" }
    end
  end

  def test_provider_menu_visibility_uses_current_request_and_hides_empty_menu
    with_provider_menu_hooks do
      PluginManager.components_for(:provider_menu).replace([ProviderMenuTestFixtures::AdministratorOnly])
      session = browser(@users.first)
      session.get("/models")
      assert_equal 200, session.response.status
      assert_equal [ProviderMenuTestFixtures::Alpha.label],
        Nokogiri::HTML(session.response.body).css("#providers-menu a.dropdown-item").map { |item| item.text.strip }

      session = browser(@users.last)
      session.get("/models")
      assert_equal 200, session.response.status
      document = Nokogiri::HTML(session.response.body)
      assert_empty document.css("#nav-link-providers, #providers-menu")

      PluginManager.components_for(:provider_menu).replace([])
      session.get("/models")
      assert_equal 200, session.response.status
      assert_empty Nokogiri::HTML(session.response.body).css("#nav-link-providers, #providers-menu")

      PluginManager.components_for(:provider_menu).replace([
        ProviderMenuTestFixtures::Hidden, Components::ManyfoldPrintables::ProviderMenuItem
      ])
      session.get("/models")
      assert_equal 200, session.response.status
      assert_equal ["Printables"],
        Nokogiri::HTML(session.response.body).css("#providers-menu a.dropdown-item").map { |item| item.text.strip }
    end
  end

  def test_two_plugins_share_one_helper_for_both_host_load_orders
    helper = File.read(File.expand_path("../lib/manyfold/provider_menu.rb", __dir__))
    [[:alpha, :zulu], [:zulu, :alpha]].each do |order|
      Dir.mktmpdir("provider-menu-load-test-") do |directory|
        order.each_with_index do |provider, index|
          path = File.join(directory, "#{index}-#{provider}")
          FileUtils.mkdir_p(File.join(path, "lib/manyfold"))
          File.write(File.join(path, "lib/manyfold/provider_menu.rb"), helper)
          File.write(File.join(path, "#{provider}_provider.gemspec"), <<~RUBY)
            Gem::Specification.new do |spec|
              spec.name = "#{provider}_provider"
              spec.version = "0.0.0"
              spec.summary = "Example provider"
              spec.authors = ["Example"]
              spec.metadata["manyfold_version"] = ">= 0.146.0"
            end
          RUBY
          File.write(File.join(path, "lib/#{provider}_provider.rb"), <<~RUBY)
            require "manyfold/provider_menu"
            class #{provider.capitalize}Provider < Components::Base
              def self.label
                "#{provider.capitalize}"
              end
            end
            2.times { Manyfold::ProviderMenu.register(#{provider.capitalize}Provider) }
          RUBY
        end
        program = <<~RUBY
          require "singleton"
          require "pathname"
          module Components
            class Base; end
          end
          require "/usr/src/app/lib/plugin_manager"
          PluginManager.load!
          PluginManager.require!
          abort "Duplicate shared helper" unless $LOADED_FEATURES.count { |path| path.end_with?("/manyfold/provider_menu.rb") } == 1
          abort "Duplicate dropdown" unless PluginManager.components_for(:navbar) == [Manyfold::ProviderMenu::Dropdown]
          labels = PluginManager.components_for(:provider_menu).map(&:label)
          abort "Missing provider" unless labels == #{order.map { |provider| provider.to_s.capitalize }.inspect}
          puts "Shared helper loaded once; both providers registered."
        RUBY
        stdout, stderr, status = Open3.capture3({"PLUGINS_PATH" => directory}, RbConfig.ruby, "-e", program)
        assert status.success?, "Host load order #{order.inspect} failed: #{stderr}#{stdout}"
        assert_equal "Shared helper loaded once; both providers registered.\n", stdout
      end
    end
  end

  private

  def with_provider_menu_hooks
    hooks = [:navbar, :provider_menu].to_h { |hook| [hook, PluginManager.components_for(hook)] }
    originals = hooks.transform_values(&:dup)
    yield originals
  ensure
    hooks&.each { |hook, components| components.replace(originals.fetch(hook)) }
  end
end
