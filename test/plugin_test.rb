# frozen_string_literal: true

abort "Run this test with bin/test in its disposable Manyfold container." unless
  ENV["MANYFOLD_PRINTABLES_TEST"] == "1" && defined?(Rails.application)

require "minitest/autorun"
require "action_dispatch/testing/integration"
require "active_support/testing/time_helpers"
require "active_job/queue_adapters/test_adapter"
require "warden/test/helpers"
require "nokogiri"
require "tmpdir"
require "fileutils"

ActiveJob::Base.queue_adapter = :test
Warden.test_mode!

class PrintablesPluginTest < Minitest::Test
  include Warden::Test::Helpers
  include ActiveSupport::Testing::TimeHelpers

  SETTINGS = %w[printables_enabled].freeze

  def self.runnable_methods
    super.sort
  end

  def setup
    @original_settings = SETTINGS.to_h { |key| [key, SiteSettings.find_by(var: key)&.attributes] }
    SETTINGS.each { |key| SiteSettings.find_by(var: key)&.destroy! }
    SiteSettings.printables_enabled = true
    @original_csrf = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @library_path = Dir.mktmpdir("printables-status-test-")
    @library = Library.create!(name: "Status test", path: @library_path,
      storage_service: "filesystem", path_template: "{creator}/{modelName}")
    @users = [:administrator, :member].map do |role|
      identifier = SecureRandom.hex(8)
      User.create!(username: "status-#{identifier}", email: "#{identifier}@example.invalid",
        password: "Local-test-#{SecureRandom.hex(16)}", approved: true).tap { |user| user.add_role(role) }
    end
  end

  def teardown
    Warden.test_reset!
    @users&.each { |user| user.destroy! }
    @library&.destroy!
    @original_settings.each do |key, attributes|
      SiteSettings.find_by(var: key)&.destroy!
      SiteSettings.create!(attributes) if attributes
    end
    ActionController::Base.allow_forgery_protection = @original_csrf
    FileUtils.remove_entry(@library_path) if @library_path && File.exist?(@library_path)
  end

  def test_real_host_navigation_and_empty_status_for_both_roles_and_mount_prefixes
    assert_kind_of Rails::Engine, ManyfoldPrintables::Engine.instance
    version = ENV["MANYFOLD_PRINTABLES_EXPECTED_VERSION"]
    assert_equal version, PluginManager.all.fetch("manyfold_printables").version.to_s if version.present?
    assert_includes PluginManager.components_for(:navbar), Manyfold::ProviderMenu::Dropdown
    assert_includes PluginManager.components_for(:provider_menu), Components::ManyfoldPrintables::ProviderMenuItem
    @users.each do |user|
      [true, false].each do |enabled|
        ["", "/manyfold"].each do |prefix|
          SiteSettings.printables_enabled = enabled
          session = browser(user)
          session.get("/models", env: {"SCRIPT_NAME" => prefix})
          assert_equal 200, session.response.status
          document = Nokogiri::HTML(session.response.body)
          assert_equal 1, document.css("#main-navbar #providers-menu").size
          assert_equal ["Printables"], document.css("#providers-menu a.dropdown-item").map { |item| item.text.strip }
          item = document.at_css("#providers-menu a.dropdown-item")
          assert_equal "#{prefix}/manyfold_printables", item["href"].delete_suffix("/")
          refute_nil item.at_css('.bi-box-seam')
          session.get(item["href"].delete_prefix(prefix), env: {"SCRIPT_NAME" => prefix})
          assert_equal 200, session.response.status
          status = Nokogiri::HTML(session.response.body)
          assert_empty status.css("main table")
          refute status.css('a[href]').any? { |link| link["href"].include?("/manyfold_printables/import") }
          refute status.css('a[href]').any? { |link| link["href"].include?("/create_model") }
        end
      end
    end
  end

  private

  def browser(user)
    Warden.test_reset!
    login_as(user, scope: :user)
    ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host!(PublicUrl.hostname)
      session.https! if Rails.application.config.assume_ssl
    end
  end

end

Dir[File.join(__dir__, "*_test.rb")].sort.each { |path| require path unless path == __FILE__ }
