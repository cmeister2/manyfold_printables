# frozen_string_literal: true

require "uri"
require "cgi"

# Fictional names, identifiers and creator metadata only.
class PrintablesPluginTest
  class FakeLinkClient
    attr_reader :calls, :search_calls

    def initialize(payload)
      @payload = payload
      @calls = []
      @search_calls = []
    end

    def object(id)
      @calls << id.to_s
      Marshal.load(Marshal.dump(@payload))
    end

    def search(query, limit:)
      @search_calls << [query, limit]
      []
    end
  end

  def test_link_menu_fuzzy_search_and_selection_work_with_mount_prefixes
    SiteSettings.printables_enabled = true
    assert_includes PluginManager.components_for(:model_menu), Components::ManyfoldPrintables::ModelMenu
    ["", "/manyfold"].each do |prefix|
      with_remote_search_results do |queries|
        with_native_model(name: "Coppre Drgaon_supported.stl") do |model|
          session = browser(@users.first)
          environment = {"SCRIPT_NAME" => prefix}
          session.get("/models/#{model.to_param}", env: environment)
          assert_equal 200, session.response.status
          document = Nokogiri::HTML(session.response.body)
          menu_link = document.css('a[href]').find { |link| link.text.strip == "Link to Printables" }
          refute_nil menu_link
          refute_nil menu_link.at_css('i.bi.bi-link-45deg')
          assert_equal "menuitem", menu_link["role"]
          assert_equal "li", menu_link.parent.name
          assert_equal "presentation", menu_link.parent["role"]
          assert_equal "ul", menu_link.parent.parent.name
          uri = URI.parse(menu_link["href"])
          assert_equal "#{prefix}/manyfold_printables/link", uri.path
          assert_equal model.to_param, CGI.parse(uri.query).fetch("model_id").first
          session.get(menu_link["href"].delete_prefix(prefix), env: environment)
          assert_equal 200, session.response.status
          document = Nokogiri::HTML(session.response.body)
          assert_equal model.name, document.at_css('input[name="match_q"]')["value"]
          search = document.at_css('#printables-match-form')
          assert_equal "get", search["method"].downcase
          assert_equal "#{prefix}/manyfold_printables/link", search["action"]
          selections = document.css('a[href]').select { |link| link.text.strip == "Use this model" }
          refute_empty selections
          selected = selections.find { |link| CGI.parse(URI.parse(link["href"]).query).fetch("source").first == "92001" }
          refute_nil selected
          assert_equal "printables-link-form", URI.parse(selected["href"]).fragment
          assert_equal model.to_param, CGI.parse(URI.parse(selected["href"]).query).fetch("model_id").first
          assert_equal model.name, CGI.parse(URI.parse(selected["href"]).query).fetch("match_q").first
          session.get(selected["href"].delete_prefix(prefix).split("#").first, env: environment)
          assert_equal 200, session.response.status
          form = link_form_document(session)
          assert_equal "92001", form.at_css('input[name="source"]')["value"]
          assert_equal "#{prefix}/manyfold_printables/link", form["action"]

          session.get("/manyfold_printables/link", params: {model_id: model.to_param, match_q: "Clockwrok Badger"}, env: environment)
          assert_equal 200, session.response.status
          document = Nokogiri::HTML(session.response.body)
          assert_equal "Clockwrok Badger", document.at_css('input[name="match_q"]')["value"]
          selections = document.css('a[href]').select { |link| link.text.strip == "Use this model" }
          assert_equal ["92002"], selections.map { |link| CGI.parse(URI.parse(link["href"]).query).fetch("source").first }
          assert_empty link_jobs
          assert_empty model.links.reload
          assert_equal ["coppre drgaon", "coppre drgaon", "clockwrok badger"], queries
        end
      end
    end
  end

  def test_link_menu_tracks_integration_enable_setting
    with_native_model do |model|
      session = browser(@users.first)
      [true, false, true].each do |enabled|
        SiteSettings.printables_enabled = enabled
        session.get("/models/#{model.to_param}")
        assert_equal 200, session.response.status
        document = Nokogiri::HTML(session.response.body)
        model_links = document.css('a[href]').select { |link| link.text.strip == "Link to Printables" }
        assert_equal enabled ? 1 : 0, model_links.size
        provider_link = document.css('#providers-menu a.dropdown-item').find { |link| link.text.strip == "Printables" }
        refute_nil provider_link
        assert_equal "/manyfold_printables", provider_link["href"].delete_suffix("/")
        session.get(provider_link["href"])
        assert_equal 200, session.response.status
      end
      assert_empty link_jobs
      assert_empty model.links.reload
    end
  end

  def test_search_failure_keeps_manual_linking_available_and_disabled_integration_does_not_search
    with_native_model do |model|
      session = browser(@users.first)
      client = FakeLinkClient.new(fake_link_payload)
      client.define_singleton_method(:search) do |query, limit:|
        search_calls << [query, limit]
        raise ManyfoldPrintables::ApiClient::Unavailable, "Fictional search is unavailable."
      end
      with_link_client(client) do
        session.get("/manyfold_printables/link", params: {model_id: model.to_param})
      end
      assert_equal 200, session.response.status
      assert_includes session.response.body, "Fictional search is unavailable."
      form = link_form_document(session)
      refute form.at_css('input[type="submit"]')["disabled"]
      assert_equal [["copper dragon", 20]], client.search_calls
      assert_empty client.calls
      post_link(session, model, "https://www.printables.com/model/92001-example", form)
      assert_equal 303, session.response.status
      assert_equal [model.id, @users.first.id, "92001"], link_jobs.last[:args]
      SiteSettings.printables_enabled = false
      with_link_client(client) do
        session.get("/manyfold_printables/link", params: {model_id: model.to_param})
      end
      assert_equal 200, session.response.status
      assert_equal [["copper dragon", 20]], client.search_calls
      assert link_form_document(session).at_css('input[type="submit"]')["disabled"]
    end
  end

  def test_empty_or_numeric_only_search_keeps_manual_link_form_without_remote_requests
    with_native_model do |model|
      session = browser(@users.first)
      client = FakeLinkClient.new(fake_link_payload)
      ["", " _-- ", "1234"].each do |query|
        with_link_client(client) do
          session.get("/manyfold_printables/link", params: {model_id: model.to_param, match_q: query})
        end
        assert_equal 200, session.response.status
        assert_empty client.search_calls
        refute link_form_document(session).at_css('input[type="submit"]')["disabled"]
        assert_empty link_jobs
      end
    end
  end

  def test_link_manual_entry_queues_only_the_selected_existing_model
    SiteSettings.printables_enabled = true
    with_native_model do |model|
      ["", "/manyfold"].each do |prefix|
        session = browser(@users.first)
        form = get_link_form(session, model, prefix)
        assert_equal "", form.at_css('input[name="source"]')["value"].to_s
        document = Nokogiri::HTML(session.response.body)
        assert_empty document.css('a[href]').select { |link| link.text.strip == "Use this model" }
        ids_before = ::Model.order(:id).pluck(:id)
        ["92001", "https://www.printables.com/model/92001-fictional-example"].each do |source|
          post_link(session, model, source, form, prefix)
          assert_equal 303, session.response.status
          assert_equal "#{session.request.base_url}#{prefix}/models/#{model.to_param}", session.response.location
          refute_empty link_jobs, "No sync job was queued with mount prefix #{prefix.inspect}."
          assert link_jobs.all? { |job| job[:args] == [model.id, @users.first.id, "92001"] }
          assert_equal ids_before, ::Model.order(:id).pluck(:id)
          assert_empty model.links.reload
          form = get_link_form(session, model, prefix)
        end
      end
    end
  end

  def test_link_rejects_invalid_sources_disabled_integration_and_csrf_without_mutations
    SiteSettings.printables_enabled = true
    with_native_model do |model|
      session = browser(@users.first)
      ids_before = ::Model.order(:id).pluck(:id)
      invalid_sources = ["", "0", "not-an-id", "https://example.invalid/model/92001-example",
        "https://www.printables.com.example.invalid/model/92001-example",
        "https://user@www.printables.com/model/92001-example", ["92001"]]
      invalid_sources.each do |source|
        form = get_link_form(session, model)
        post_link(session, model, source, form)
        assert_equal 422, session.response.status
        expected = source.is_a?(String) ? source : ""
        assert_equal expected, link_form_document(session).at_css('input[name="source"]')["value"].to_s
        assert_equal "Copper Dragon", Nokogiri::HTML(session.response.body).at_css('input[name="match_q"]')["value"]
        assert_empty link_jobs
        assert_empty model.links.reload
        assert_equal ids_before, ::Model.order(:id).pluck(:id)
      end

      SiteSettings.printables_enabled = false
      form = get_link_form(session, model)
      post_link(session, model, "92001", form)
      assert_equal 422, session.response.status
      assert_equal "92001", link_form_document(session).at_css('input[name="source"]')["value"]
      assert_empty link_jobs
      assert_empty model.links.reload

      SiteSettings.printables_enabled = true
      session.post("/manyfold_printables/link", params: {model_id: model.to_param, source: "92001"},
        headers: {"HTTP_ORIGIN" => session.request.base_url})
      assert_equal 422, session.response.status
      assert_empty link_jobs
      assert_empty model.links.reload
      assert_equal ids_before, ::Model.order(:id).pluck(:id)
    end
  end

  def test_link_requires_admin_existing_model_and_sync_permission
    SiteSettings.printables_enabled = true
    with_native_model do |model|
      session = browser(@users.last)
      session.get("/models/#{model.to_param}")
      assert_equal 200, session.response.status
      document = Nokogiri::HTML(session.response.body)
      refute document.css('a[href]').any? { |link| link.text.include?("Link to Printables") }
      token = document.at_css('meta[name="csrf-token"]')["content"]
      origin = session.request.base_url
      session.get("/manyfold_printables/link", params: {model_id: model.to_param})
      assert_equal 404, session.response.status
      session.post("/manyfold_printables/link", params: {model_id: model.to_param, source: "92001", authenticity_token: token},
        headers: {"HTTP_ORIGIN" => origin})
      assert_equal 404, session.response.status
      assert_empty link_jobs
      assert_empty model.links.reload

      session = browser(@users.first)
      form = get_link_form(session, model)
      token = form.at_css('input[name="authenticity_token"]')["value"]
      origin = session.request.base_url
      session.get("/manyfold_printables/link", params: {model_id: "missing-fictional-model"})
      assert_equal 404, session.response.status
      session.post("/manyfold_printables/link", params: {model_id: "missing-fictional-model", source: "92001", authenticity_token: token},
        headers: {"HTTP_ORIGIN" => origin})
      assert_equal 404, session.response.status

      model.federails_actor.update_columns(local: false)
      refute ::ModelPolicy.new(@users.first, model.reload).sync?
      session.get("/manyfold_printables/link", params: {model_id: model.to_param})
      assert_equal 404, session.response.status
      session.post("/manyfold_printables/link", params: {model_id: model.to_param, source: "92001", authenticity_token: token},
        headers: {"HTTP_ORIGIN" => origin})
      assert_equal 404, session.response.status
      assert_empty link_jobs
      assert_empty model.links.reload
    end
  end

  def test_link_sync_updates_metadata_without_creating_models_or_moving_files
    SiteSettings.printables_enabled = true
    with_native_model do |model|
      model.update!(tag_list: ["existing"])
      ids_before = ::Model.order(:id).pluck(:id)
      path_before = model.path
      public_id_before = model.public_id
      owners_before = model.owners.order(:id).pluck(:id)
      client = FakeLinkClient.new(fake_link_payload)
      with_link_client(client) do
        2.times { ManyfoldPrintables::SyncJob.perform_now(model.id, @users.first.id, "92001") }
      end
      assert_equal ["92001", "92001"], client.calls
      model.reload
      assert_equal "Linked Copper Dragon", model.name
      assert_includes model.notes, "Fictional description."
      assert_equal ["example", "existing", "linked"], model.tag_list.sort
      assert_equal "CC-BY-4.0", model.license
      assert_equal "Example Linking Studio", model.creator.name
      assert_equal path_before, model.path
      assert_equal public_id_before, model.public_id
      assert_equal owners_before, model.owners.order(:id).pluck(:id)
      assert_equal model.name.parameterize, model.slug
      refute_equal fake_link_payload["slug"], model.slug
      assert_equal ids_before, ::Model.order(:id).pluck(:id)
      assert_equal 1, model.links.size
      link = model.links.first
      assert_equal ManyfoldPrintables::Source.canonical_url(fake_link_payload), link.url
      refute_nil link.synced_at
      assert_equal [], model.model_files.to_a
    end
  end

  def test_link_sync_rechecks_permissions_before_api_calls_and_link_creation
    SiteSettings.printables_enabled = true
    with_native_model do |model|
      client = FakeLinkClient.new(fake_link_payload)
      original = model.attributes
      with_link_client(client) do
        ManyfoldPrintables::SyncJob.perform_now(model.id, @users.last.id, "92001")
        assert_empty client.calls
        assert_empty model.links.reload
        assert_equal original, model.reload.attributes
        model.federails_actor.update_columns(local: false)
        ManyfoldPrintables::SyncJob.perform_now(model.id, @users.first.id, "92001")
        model.federails_actor.update_columns(local: true)
        SiteSettings.printables_enabled = false
        ManyfoldPrintables::SyncJob.perform_now(model.id, @users.first.id, "92001")
      end
      assert_empty client.calls
      assert_empty model.links.reload
      assert_equal original, model.reload.attributes
    end
  end

  def test_link_sync_rejects_an_unexpected_api_model_before_creating_a_link
    SiteSettings.printables_enabled = true
    with_native_model do |model|
      original = model.attributes
      client = FakeLinkClient.new(fake_link_payload.merge("id" => 92099))
      with_link_client(client) do
        ManyfoldPrintables::SyncJob.perform_now(model.id, @users.first.id, "92001")
      end
      assert_equal ["92001"], client.calls
      assert_empty model.links.reload
      assert_equal original, model.reload.attributes
    end
  end

  private

  def with_remote_search_results
    queries = []
    results = [{"id" => "92001", "name" => "Copper Dragon", "user" => {"publicUsername" => "Fictional studio"}},
      {"id" => "92002", "name" => "Clockwork Badger", "user" => {"publicUsername" => "Fictional studio"}},
      {"id" => "92003", "name" => "Unrelated Desert Castle", "user" => nil}]
    connection = Faraday.new do |builder|
      builder.response :json
      builder.adapter :test do |adapter|
        adapter.post(ManyfoldPrintables::ApiClient::BASE_URL) do |environment|
          query = JSON.parse(environment.body)
          queries << query.fetch("variables").fetch("query")
          [200, {"Content-Type" => "application/json"}, JSON.generate("data" => {"searchPrints2" => {"items" => results}})]
        end
      end
    end
    client = ManyfoldPrintables::ApiClient.new(connection: connection)
    with_link_client(client) { yield queries }
  end

  def with_link_client(client)
    api_client = ManyfoldPrintables::ApiClient
    singleton = api_client.singleton_class
    original_constructor = api_client.method(:new)
    own_constructor = singleton.instance_methods(false).include?(:new)
    singleton.send(:define_method, :new) { |*arguments, **options, &block| client }
    yield
  ensure
    if own_constructor
      singleton.send(:define_method, :new, original_constructor)
    else
      singleton.send(:remove_method, :new)
    end
  end

  def with_native_model(name: "Copper Dragon")
    creators_before = ::Creator.pluck(:id)
    tags_before = ActsAsTaggableOn::Tag.pluck(:id)
    adapter = ActiveJob::Base.queue_adapter
    jobs_before = adapter.enqueued_jobs.dup
    path = "fictional-link-model-#{SecureRandom.hex(8)}"
    FileUtils.mkdir_p(File.join(@library_path, path))
    model = ::Model.create!(library: @library, name: name, path: path, permission_preset: "member", owner: @users.first)
    yield model
  ensure
    model&.federails_actor&.update_columns(local: true) if model&.persisted?
    model&.destroy!
    ::Creator.where.not(id: creators_before).find_each(&:destroy!) if creators_before
    ActsAsTaggableOn::Tag.where.not(id: tags_before).destroy_all if tags_before
    adapter&.enqueued_jobs&.replace(jobs_before) if jobs_before
  end

  def get_link_form(session, model, prefix = "")
    with_link_client(FakeLinkClient.new(fake_link_payload)) do
      session.get("/manyfold_printables/link", params: {model_id: model.to_param}, env: {"SCRIPT_NAME" => prefix})
    end
    assert_equal 200, session.response.status
    link_form_document(session)
  end

  def link_form_document(session)
    form = Nokogiri::HTML(session.response.body).at_css('#printables-link-form')
    refute_nil form
    assert_equal "post", form["method"].downcase
    assert_equal "Link and sync", form.at_css('input[type="submit"]')["value"]
    form
  end

  def post_link(session, model, source, form, prefix = "")
    token = form.at_css('input[name="authenticity_token"]')["value"]
    with_link_client(FakeLinkClient.new(fake_link_payload)) do
      session.post("/manyfold_printables/link", params: {model_id: model.to_param, source: source, match_q: "Copper Dragon", authenticity_token: token},
        env: {"SCRIPT_NAME" => prefix}, headers: {"HTTP_ORIGIN" => session.request.base_url})
    end
  end

  def link_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == ManyfoldPrintables::SyncJob }
  end

  def fake_link_payload
    {"id" => "92001", "name" => "Linked Copper Dragon", "description" => "<p>Fictional description.</p>",
      "slug" => "untrusted-provider-slug", "path" => "unexpected/provider/path",
      "tags" => [{"name" => "example"}, {"name" => "linked"}],
      "license" => {"id" => "1", "name" => "Creative Commons \u2014 Attribution"}, "images" => [], "image" => nil,
      "user" => {"id" => "9001", "publicUsername" => "Example Linking Studio", "handle" => "example-linking-studio",
        "bio" => "", "avatarFilePath" => nil, "bannerFilePath" => nil}}
  end
end
