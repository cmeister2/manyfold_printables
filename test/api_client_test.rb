# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "faraday"

# Sanitized GraphQL fixtures exercise the real Faraday JSON request pipeline.
class PrintablesApiClientTest < Minitest::Test
  Client = ManyfoldPrintables::ApiClient

  def test_public_model_lookup_uses_graphql_variables_without_credentials
    payload = {"id" => "92001", "name" => "Fictional model"}
    client, requests = stub_client({"data" => {"print" => payload}})
    assert_equal payload, client.object("92001")
    assert_equal 1, requests.size
    request = requests.first
    assert_equal Client::BASE_URL, request[:url]
    assert_equal({"id" => "92001"}, request[:body]["variables"])
    assert_includes request[:body]["query"], "print(id: $id)"
    assert_equal "application/json", request[:headers]["Accept"]
    assert_equal "application/json", request[:headers]["Content-Type"]
    refute request[:headers].key?("Authorization")
    assert_empty URI.parse(request[:url]).query.to_s
  end

  def test_creator_lookup_uses_a_handle_variable_and_checks_identity
    payload = {"id" => "9001", "handle" => "example-studio", "publicUsername" => "Fictional studio"}
    client, requests = stub_client({"data" => {"user" => payload}})
    assert_equal payload, client.creator("example-studio")
    assert_equal({"id" => "@example-studio"}, requests.first[:body]["variables"])
    assert_includes requests.first[:body]["query"], "user(id: $id)"
    refute requests.first[:headers].key?("Authorization")
    [payload.merge("id" => nil), payload.merge("handle" => "other-studio"), {}, []].each do |response|
      client, = stub_client({"data" => {"user" => response}})
      assert_raises(Client::InvalidResponse) { client.creator("example-studio") }
    end
  end

  def test_invalid_model_ids_and_handles_do_not_send_requests
    [nil, "", "0", "01", "../92001", "https://example.invalid/model/92001"].each do |source|
      client, requests = stub_client
      assert_raises(Client::InvalidObjectId) { client.object(source) }
      assert_empty requests
    end
    [nil, "", "example studio", "studio/other", 'studio") { privateData }', ["studio"]].each do |handle|
      client, requests = stub_client
      assert_raises(Client::InvalidObjectId) { client.creator(handle) }
      assert_empty requests
    end
  end

  def test_model_responses_reject_mismatched_or_incomplete_identity
    [{"id" => "92002", "name" => "Wrong model"}, {"id" => "92001"}, [], true].each do |payload|
      client, = stub_client({"data" => {"print" => payload}})
      assert_raises(Client::InvalidResponse) { client.object("92001") }
    end
    client, = stub_client({"data" => {"print" => nil}})
    assert_raises(Client::NotFound) { client.object("92001") }
    client, = stub_client({"data" => {"user" => nil}})
    assert_raises(Client::NotFound) { client.creator("example-studio") }
  end

  def test_partial_graphql_errors_and_invalid_json_do_not_expose_server_details
    [{"data" => {"print" => {"id" => "92001", "name" => "Fictional"}}, "errors" => [{"message" => "fictional-private-server-detail"}]},
      {"data" => nil}, {"errors" => "fictional-private-server-detail"}, []].each do |payload|
      client, = stub_client(payload)
      error = assert_raises(Client::InvalidResponse) { client.object("92001") }
      refute_includes error.message, "fictional-private-server-detail"
    end
    client, = stub_client("{broken fictional-private-server-detail", raw: true)
    error = assert_raises(Client::InvalidResponse) { client.object("92001") }
    assert_nil error.cause
    refute_includes error.message, "fictional-private-server-detail"
  end

  def test_http_and_network_failures_are_safe_and_specific
    {401 => Client::AuthenticationError, 403 => Client::AuthenticationError, 404 => Client::NotFound,
      429 => Client::RateLimited, 500 => Client::Unavailable}.each do |status, error_class|
      client, = stub_client({"message" => "fictional-private-server-detail"}, status: status)
      error = assert_raises(error_class) { client.object("92001") }
      refute_includes error.message, "fictional-private-server-detail"
    end
    client, = stub_client(network_error: true)
    error = assert_raises(Client::Unavailable) { client.object("92001") }
    assert_nil error.cause
    refute_includes error.message, "fictional-private-server-detail"
  end

  def test_remote_search_uses_graphql_variables_and_returns_public_results
    results = [{"id" => "92001", "name" => "Copper Dragon", "user" => {"publicUsername" => "Fictional studio"}}]
    client, requests = stub_client({"data" => {"searchPrints2" => {"items" => results}}})
    query = 'Copper Dragon" } privateData'
    assert_equal results, client.search(query, limit: 10)
    assert_equal({"query" => query, "limit" => 10}, requests.first[:body]["variables"])
    assert_includes requests.first[:body]["query"], "searchPrints2(query: $query"
    refute_includes requests.first[:body]["query"], "privateData"
    refute requests.first[:headers].key?("Authorization")
  end

  def test_empty_or_invalid_searches_do_not_request_remote_data
    client, requests = stub_client
    assert_empty client.search(" ")
    [nil, ["dragon"], "dragon\n", "x" * 201].each do |query|
      assert_raises(Client::InvalidSearch) { client.search(query) }
    end
    [0, 21, "5", nil].each do |limit|
      assert_raises(Client::InvalidSearch) { client.search("Dragon", limit: limit) }
    end
    assert_empty requests
  end

  def test_incomplete_or_oversized_search_results_are_rejected
    [nil, {}, [{"id" => "0", "name" => "Invalid"}], [{"id" => "92001", "name" => "Model", "user" => []}],
      Array.new(21, {"id" => "92001", "name" => "Model"})].each do |items|
      client, = stub_client({"data" => {"searchPrints2" => {"items" => items}}})
      assert_raises(Client::InvalidResponse) { client.search("Dragon") }
    end
  end

  private

  def stub_client(payload = {"data" => {}}, status: 200, raw: false, network_error: false)
    requests = []
    connection = Faraday.new do |builder|
      builder.response :json
      builder.adapter :test do |adapter|
        adapter.post(Client::BASE_URL) do |environment|
          requests << {url: environment.url.to_s, body: JSON.parse(environment.body), headers: environment.request_headers}
          raise Faraday::TimeoutError, "fictional-private-server-detail" if network_error
          [status, {"Content-Type" => "application/json"}, raw ? payload : JSON.generate(payload)]
        end
      end
    end
    [Client.new(connection: connection), requests]
  end
end
