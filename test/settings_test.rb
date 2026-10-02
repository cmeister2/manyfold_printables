# frozen_string_literal: true

class PrintablesPluginTest
  def test_integration_settings_has_a_separate_enable_form_and_keeps_native_provider_credentials
    originals = %w[myminifactory_api_key cults3d_api_key thingiverse_api_key].to_h { |key| [key, SiteSettings.public_send(key)] }
    originals.keys.each { |key| SiteSettings.public_send("#{key}=", "fictional-native-#{key}") }
    ["", "/manyfold"].each do |prefix|
      session = browser(@users.first)
      [true, false].each do |enabled|
        SiteSettings.printables_enabled = enabled
        form = printables_settings_form(session, prefix)
        checkbox = form.at_css('input[type="checkbox"][name="enabled"]')
        refute_nil checkbox
        assert_equal enabled, checkbox.key?("checked")
        assert_empty form.ancestors("form")
        assert_empty form.css('input[type="password"], textarea')
        assert_equal %w[checkbox submit], form.css('input:not([type="hidden"])').map { |input| input["type"] }
        document = Nokogiri::HTML(session.response.body)
        originals.keys.each { |key| refute_nil document.at_css("input[name='integrations[#{key}]']") }
        post_printables_settings(session, form, {enabled: enabled ? "0" : "1"}, prefix)
        assert_equal 303, session.response.status
        assert_equal "#{session.request.base_url}#{prefix}/settings/integrations", session.response.location
        assert_equal !enabled, SiteSettings.printables_enabled
        originals.keys.each { |key| assert_equal "fictional-native-#{key}", SiteSettings.public_send(key) }
      end
    end
  ensure
    originals&.each { |key, value| SiteSettings.public_send("#{key}=", value) }
  end

  def test_settings_omitted_enable_field_keeps_existing_value
    SiteSettings.printables_enabled = false
    session = browser(@users.first)
    form = printables_settings_form(session)
    post_printables_settings(session, form, {})
    assert_equal 303, session.response.status
    assert_equal false, SiteSettings.printables_enabled
  end

  def test_printables_settings_require_admin_and_csrf
    SiteSettings.printables_enabled = true
    session = browser(@users.first)
    printables_settings_form(session)
    session.patch("/manyfold_printables/settings", params: {enabled: "0"}, headers: {"HTTP_ORIGIN" => session.request.base_url})
    assert_equal 422, session.response.status
    assert_equal true, SiteSettings.printables_enabled
    session = browser(@users.last)
    session.get("/manyfold_printables/")
    token = Nokogiri::HTML(session.response.body).at_css('meta[name="csrf-token"]')["content"]
    session.patch("/manyfold_printables/settings", params: {enabled: "0", authenticity_token: token}, headers: {"HTTP_ORIGIN" => session.request.base_url})
    assert_equal 404, session.response.status
    assert_equal true, SiteSettings.printables_enabled
  end

  private

  def printables_settings_form(session, prefix = "")
    session.get("/settings/integrations", env: {"SCRIPT_NAME" => prefix})
    assert_equal 200, session.response.status
    form = Nokogiri::HTML(session.response.body).at_css('#printables-settings-form')
    refute_nil form
    assert_equal "#{prefix}/manyfold_printables/settings", form["action"]
    form
  end

  def post_printables_settings(session, form, parameters, prefix = "")
    token = form.at_css('input[name="authenticity_token"]')["value"]
    session.patch("/manyfold_printables/settings", params: parameters.merge(authenticity_token: token),
      env: {"SCRIPT_NAME" => prefix}, headers: {"HTTP_ORIGIN" => session.request.base_url})
  end
end
