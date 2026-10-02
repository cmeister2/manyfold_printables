# frozen_string_literal: true

require "minitest/autorun"
require "faraday"

# Fictional public profiles; no authenticated account information.
class PrintablesCreatorServicesTest < Minitest::Test
  Source = ManyfoldPrintables::CreatorSource
  Deserializer = ManyfoldPrintables::CreatorDeserializer
  Client = ManyfoldPrintables::ApiClient
  PROFILE_URL = "https://www.printables.com/@example-studio"

  def setup
    @original_enabled = SiteSettings.printables_enabled
    SiteSettings.printables_enabled = true
  end

  def teardown
    SiteSettings.printables_enabled = @original_enabled
  end

  def test_profile_tabs_and_locales_share_a_canonical_handle
    ["", "en/", "de/"].each do |locale|
      ["", "/", "/models", "/collections", "/makes", "/club"].each do |suffix|
        source = Source.new("http://printables.com/#{locale}@example-studio#{suffix}?page=2#profile")
        assert_equal "example-studio", source.username
        assert_equal PROFILE_URL, source.uri
      end
    end
    source = Source.from_payload(creator_payload)
    assert_equal "9001", source.id
    assert source.matches?(creator_payload)
    refute source.matches?(creator_payload.merge("id" => "9002"))
    assert_equal "https://www.printables.com/@studio_123", Source.from_payload(creator_payload.merge("handle" => "studio_123")).uri
  end

  def test_profile_parser_and_payload_reject_unsafe_or_incomplete_identity
    [nil, "", "example-studio", "https://printables.com.example.invalid/@studio",
      "https://example.invalid/@studio", "ftp://printables.com/@studio",
      "https://user:password@printables.com/@studio", "https://printables.com:80/@studio",
      "http://printables.com:443/@studio", "https://printables.com:444/@studio",
      "https://printables.com/model/92001", "https://printables.com/users/studio",
      "https://printables.com/@studio/settings", "https://printables.com/@a%2Fb",
      "https://printables.com/@studio%00", "https://printables.com/@%FF",
      "https://printables.com/@..", "https://printables.com/@%20studio"].each do |url|
      assert_raises(Source::Invalid, url.inspect) { Source.new(url) }
    end
    [nil, {}, creator_payload.merge("id" => nil), creator_payload.merge("handle" => "bad/handle")].each do |payload|
      assert_raises(Source::Invalid) { Source.from_payload(payload) }
      refute Source.new(PROFILE_URL).matches?(payload)
    end
    creator = Struct.new(:links).new([Struct.new(:url).new("https://printables.com/model/92001")])
    refute Source.linked?(creator)
    creator.links << Struct.new(:url).new("http://printables.com/en/@example-studio/models")
    assert Source.linked?(creator)
  end

  def test_cached_profile_maps_name_bio_avatar_and_banner_without_another_request
    with_client(Object.new) do
      deserializer = Deserializer.new(uri: PROFILE_URL, payload: creator_payload)
      assert deserializer.valid?(for_class: ::Creator)
      refute deserializer.valid?(for_class: ::Model)
      assert_equal({name: "Fictional Example Studio", slug: "example-studio", notes: "A **fictional** studio.",
        links_attributes: [{url: PROFILE_URL}], avatar_remote_url: "https://media.printables.com/media/auth/9001/avatar.png",
        banner_remote_url: "https://media.printables.com/media/auth/9001/banner.png"}, deserializer.deserialize)
    end
  end

  def test_sparse_and_unsafe_profile_fields_are_omitted
    [nil, "https://example.invalid/avatar.png", "media/auth/../secret.png", "media/auth/avatar%00.png", ["media/auth/avatar.png"]].each do |image|
      attributes = Deserializer.new(uri: PROFILE_URL, payload: creator_payload.merge(
        "bio" => nil, "publicUsername" => nil, "avatarFilePath" => image, "bannerFilePath" => image)).deserialize
      assert_equal "example-studio", attributes[:name]
      refute attributes.key?(:notes)
      refute attributes.key?(:avatar_remote_url)
      refute attributes.key?(:banner_remote_url)
    end
    assert_raises(Client::InvalidResponse) do
      Deserializer.new(uri: PROFILE_URL, payload: creator_payload.merge("handle" => "other-studio")).deserialize
    end
  end

  def test_native_resync_uses_the_handle_and_converts_failures_to_safe_link_errors
    client = Object.new
    calls = []
    payload = creator_payload
    client.define_singleton_method(:creator) { |handle| calls << handle; payload }
    with_client(client) { assert_equal "A **fictional** studio.", Deserializer.new(uri: PROFILE_URL).deserialize[:notes] }
    assert_equal ["example-studio"], calls
    [Client::Unavailable.new("Fictional API failure."), creator_payload.merge("handle" => "other-studio")].each do |response|
      client.define_singleton_method(:creator) { |_handle| raise response if response.is_a?(Exception); response }
      with_client(client) do
        error = assert_raises(Faraday::Error) { Deserializer.new(uri: PROFILE_URL).deserialize }
        assert_nil error.cause
      end
    end
  end

  def test_factory_handles_creators_and_models_once_and_preserves_other_providers
    2.times { ManyfoldPrintables::CreatorLinks.install! }
    assert_equal 1, ::Link.singleton_class.ancestors.count(ManyfoldPrintables::CreatorLinks::DeserializerFactory)
    assert_kind_of Deserializer, ::Link.deserializer_for(url: PROFILE_URL, for_class: ::Creator)
    assert_kind_of ManyfoldPrintables::ObjectDeserializer,
      ::Link.deserializer_for(url: "https://www.printables.com/model/92001", for_class: ::Model)
    fallback = Class.new { def self.deserializer_for(**arguments); arguments; end }
    fallback.singleton_class.prepend(ManyfoldPrintables::CreatorLinks::DeserializerFactory)
    other = "https://example.invalid/studio"
    assert_equal({url: other, for_class: ::Creator}, fallback.deserializer_for(url: other, for_class: ::Creator))
    assert_equal({url: PROFILE_URL, for_class: ::Model}, fallback.deserializer_for(url: PROFILE_URL, for_class: ::Model))
    SiteSettings.printables_enabled = false
    refute Deserializer.new(uri: PROFILE_URL, payload: creator_payload).valid?
    assert_equal({url: PROFILE_URL, for_class: ::Creator}, fallback.deserializer_for(url: PROFILE_URL, for_class: ::Creator))
    [nil, "", other, "https://printables.com/model/92001"].each do |url|
      deserializer = Deserializer.new(uri: url, payload: creator_payload)
      refute deserializer.valid?
      assert_equal({}, deserializer.deserialize)
    end
  end

  private

  def creator_payload
    {"id" => "9001", "handle" => "example-studio", "publicUsername" => " Fictional Example Studio ",
      "bio" => "<p>A <strong>fictional</strong> studio.</p>", "avatarFilePath" => "media/auth/9001/avatar.png",
      "bannerFilePath" => "media/auth/9001/banner.png"}
  end

  def with_client(client)
    singleton = Client.singleton_class
    original = Client.method(:new)
    own_constructor = singleton.instance_methods(false).include?(:new)
    singleton.send(:define_method, :new) { |*arguments, **options, &block| client }
    yield
  ensure
    own_constructor ? singleton.send(:define_method, :new, original) : singleton.send(:remove_method, :new)
  end
end
