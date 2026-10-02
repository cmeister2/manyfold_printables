# frozen_string_literal: true

class PrintablesPluginTest
  def test_integration_settings_puts_printables_in_the_native_form_and_saves_all_providers
    with_native_integration_settings do |credentials|
      ["", "/manyfold"].each do |prefix|
        session = browser(@users.first)
        [true, false].each do |enabled|
          SiteSettings.printables_enabled = enabled
          form = integration_settings_form(session, prefix)
          document = Nokogiri::HTML(session.response.body)
          checkbox = form.at_css('input[type="checkbox"][name="integrations[printables_enabled]"]')
          refute_nil checkbox
          assert_equal enabled, checkbox.key?("checked")
          assert_equal 1, checkbox.ancestors("form").size
          assert_empty form.ancestors("form")
          assert_empty form.css("form")
          label = form.at_css("label[for='#{checkbox["id"]}']")
          assert_equal "Enable Printables linking and sync", label.text.strip
          assert_equal 1, document.css("#printables-integration").size
          headers = document.css('button[data-bs-target="#printables-integration"]')
          assert_equal 1, headers.size
          assert_equal "Printables #{enabled ? "\u2705" : "\u274c"}", headers.first.text.strip
          submit_buttons = form.css('button[type="submit"], input[type="submit"]')
          assert_equal 1, submit_buttons.size
          assert_equal 1, submit_buttons.first.xpath('preceding::*[@id="printables-integration"]').size
          assert_empty document.css("#printables-settings-form")
          credentials.each do |key, value|
            input = form.at_css("input[name='integrations[#{key}]']")
            refute_nil input
            assert_equal value, input["value"]
            assert_equal form, input.ancestors("form").first
          end

          # Submit the fields a browser would send, including the checkbox's
          # hidden unchecked value, the native credentials, and CSRF token.
          enabled ? checkbox.remove_attribute("checked") : checkbox["checked"] = "checked"
          credentials["cults3d_api_username"] = "fictional-updated-#{prefix.empty? ? 'root' : 'mounted'}-#{enabled}"
          form.at_css('input[name="integrations[cults3d_api_username]"]')["value"] = credentials["cults3d_api_username"]
          submit_integration_settings(session, form, prefix)
          assert_equal 302, session.response.status
          assert_equal "#{session.request.base_url}#{prefix}/settings/integrations", session.response.location
          assert_equal !enabled, SiteSettings.printables_enabled
          credentials.each { |key, value| assert_equal value, SiteSettings.public_send(key) }
        end
      end
    end
  end

  def test_native_settings_omitted_printables_field_keeps_existing_value
    with_native_integration_settings do |credentials|
      ["", "/manyfold"].each do |prefix|
        [true, false].each do |enabled|
          SiteSettings.printables_enabled = enabled
          session = browser(@users.first)
          form = integration_settings_form(session, prefix)
          form.css('input[name="integrations[printables_enabled]"]').remove
          submit_integration_settings(session, form, prefix)
          assert_equal 302, session.response.status
          assert_equal enabled, SiteSettings.printables_enabled
          credentials.each { |key, value| assert_equal value, SiteSettings.public_send(key) }
        end
      end
    end
  end

  def test_printables_section_only_appears_on_integration_settings
    session = browser(@users.first)
    ["/settings", "/settings/appearance"].each do |path|
      session.get(path)
      assert_equal 200, session.response.status
      document = Nokogiri::HTML(session.response.body)
      assert_empty document.css('#printables-integration, input[name="integrations[printables_enabled]"]')
    end
  end

  def test_native_and_legacy_printables_settings_require_admin_and_csrf
    ["", "/manyfold"].each do |prefix|
      ["/settings", "/manyfold_printables/settings"].each do |path|
        SiteSettings.printables_enabled = true
        parameters = path == "/settings" ? {integrations: {printables_enabled: "0"}} : {enabled: "0"}
        session = browser(@users.first)
        integration_settings_form(session, prefix)
        session.patch(path, params: parameters, env: {"SCRIPT_NAME" => prefix},
          headers: {"HTTP_ORIGIN" => session.request.base_url})
        assert_equal 422, session.response.status
        assert_equal true, SiteSettings.printables_enabled

        session = browser(@users.last)
        session.get("/manyfold_printables/", env: {"SCRIPT_NAME" => prefix})
        token = Nokogiri::HTML(session.response.body).at_css('meta[name="csrf-token"]')["content"]
        session.patch(path, params: parameters.merge(authenticity_token: token), env: {"SCRIPT_NAME" => prefix},
          headers: {"HTTP_ORIGIN" => session.request.base_url})
        assert_equal 404, session.response.status
        assert_equal true, SiteSettings.printables_enabled
      end
    end
  end

  def test_legacy_printables_settings_endpoint_remains_compatible
    ["", "/manyfold"].each do |prefix|
      SiteSettings.printables_enabled = true
      session = browser(@users.first)
      integration_settings_form(session, prefix)
      token = Nokogiri::HTML(session.response.body).at_css('meta[name="csrf-token"]')["content"]
      [{enabled: "0"}, {}].each do |parameters|
        session.patch("/manyfold_printables/settings", params: parameters.merge(authenticity_token: token),
          env: {"SCRIPT_NAME" => prefix}, headers: {"HTTP_ORIGIN" => session.request.base_url})
        assert_equal 303, session.response.status
        assert_equal "#{session.request.base_url}#{prefix}/settings/integrations", session.response.location
        assert_equal false, SiteSettings.printables_enabled
      end
    end
  end

  private

  def integration_settings_form(session, prefix = "")
    session.get("/settings/integrations", env: {"SCRIPT_NAME" => prefix})
    assert_equal 200, session.response.status
    input = Nokogiri::HTML(session.response.body).at_css('input[name="integrations[cults3d_api_key]"]')
    refute_nil input
    form = input.ancestors("form").first
    refute_nil form
    assert_equal "#{prefix}/settings", form["action"]
    form
  end

  def submit_integration_settings(session, form, prefix = "")
    fields = form.css("input[name]").filter_map do |input|
      next if input.key?("disabled") || %w[submit button].include?(input["type"])
      next if %w[checkbox radio].include?(input["type"]) && !input.key?("checked")
      [input["name"], input["value"]]
    end
    parameters = Rack::Utils.parse_nested_query(URI.encode_www_form(fields))
    assert_equal "patch", parameters["_method"]
    refute_empty parameters["authenticity_token"]
    session.post(form["action"].delete_prefix(prefix), params: parameters, env: {"SCRIPT_NAME" => prefix},
      headers: {"HTTP_ORIGIN" => session.request.base_url,
                "HTTP_REFERER" => "#{session.request.base_url}#{prefix}/settings/integrations"})
  end

  def with_native_integration_settings
    originals = %w[cults3d_api_username cults3d_api_key myminifactory_api_key thingiverse_api_key].to_h do |key|
      [key, SiteSettings.public_send(key)]
    end
    credentials = originals.keys.to_h { |key| [key, "fictional-native-#{key}"] }
    credentials.each { |key, value| SiteSettings.public_send("#{key}=", value) }
    yield credentials
  ensure
    originals&.each { |key, value| SiteSettings.public_send("#{key}=", value) }
  end
end
