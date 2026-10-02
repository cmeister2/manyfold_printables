# frozen_string_literal: true

require "minitest/autorun"

# Fictional provider metadata, without account information or HTTP requests.
class PrintablesLinkServicesTest < Minitest::Test
  Source = ManyfoldPrintables::Source
  Mapper = ManyfoldPrintables::MetadataMapper

  def test_numeric_ids_and_localized_model_tabs_share_one_canonical_url
    assert_equal "92001", Source.new(" 92001 ").id
    assert_equal Source::MAX_ID.to_s, Source.new(Source::MAX_ID).id
    ["", "en/", "de/"].each do |locale|
      ["", "-example-model"].each do |slug|
        ["", "/files", "/comments", "/makes", "/related"].each do |tab|
          url = "http://printables.com/#{locale}model/92001#{slug}#{tab}/?ref=fictional#photos"
          assert_equal "92001", Source.new(url).id
        end
      end
    end
    assert_equal "https://www.printables.com/model/92001", Source.canonical_url({"id" => "92001"})
    assert_equal "https://www.printables.com/model/92001",
      Source.canonical_url({"id" => 92001, "slug" => "untrusted-slug", "url" => "https://example.invalid/ignored"})
  end

  def test_sources_reject_foreign_hosts_credentials_ports_and_invalid_ids
    [nil, "", "0", "-1", "01", "1.0", "1e5", (Source::MAX_ID + 1).to_s,
      "https://printables.com.example.invalid/model/92001", "https://example.invalid/model/92001",
      "https://user:password@www.printables.com/model/92001", "https://printables.com:80/model/92001",
      "http://printables.com:443/model/92001", "ftp://printables.com/model/92001",
      "https://printables.com/@example-creator", "https://printables.com/model/92001/download",
      "https://printables.com/model/01-example", "../92001"].each do |input|
      assert_raises(Source::Invalid, input.inspect) { Source.new(input) }
    end
    [nil, {}, {"id" => 0}, {"id" => "not-an-id"}].each do |payload|
      assert_raises(Source::Invalid) { Source.canonical_url(payload) }
    end
  end

  def test_metadata_converts_html_and_maps_only_known_fields_and_verified_license_ids
    mapper = Mapper.new({"id" => "92001", "name" => " Example sculpture ",
      "description" => "<p>A <strong>fictional</strong> sculpture.</p>",
      "summary" => "Plain fallback", "tags" => [{"name" => " example "}, {"name" => "example"}, nil,
        {"name" => ""}, {"name" => "sculpture"}],
      "license" => {"id" => "1", "name" => "Creative Commons \u2014 Attribution"},
      "slug" => "incoming-slug", "path" => "incoming-path", "owner" => "incoming-owner"})
    assert_equal %i[license name notes tag_list], mapper.attributes.keys.sort
    assert_equal "Example sculpture", mapper.attributes[:name]
    assert_includes mapper.attributes[:notes], "**fictional**"
    assert_equal %w[example sculpture], mapper.attributes[:tag_list]
    assert_equal "CC-BY-4.0", mapper.attributes[:license]
    ["Unknown commercial licence", "MIT OR Apache-2.0", "CC-BY-4.0"].each do |name|
      refute Mapper.new({"license" => {"name" => name}}).attributes.key?(:license)
    end
    refute Mapper.new({"license" => {"id" => "999", "name" => "Creative Commons \u2014 Attribution"}}).attributes.key?(:license)
    assert_equal "CC0-1.0", Mapper.new({"license" => {"id" => "7", "name" => "Creative Commons \u2014 Public Domain"}}).attributes[:license]
  end

  def test_active_html_and_unsafe_urls_are_removed_from_description
    html = '<p>Safe <a href="/model/92002">related model</a></p><script>fictionalSecret()</script>' \
      '<iframe src="https://example.invalid/tracker"></iframe><a href="javascript:evil()">bad link</a>' \
      '<img src="data:image/png;base64,FAKE"><a href="https://user:password@example.invalid">credential link</a>'
    notes = Mapper.new({"id" => "92001", "description" => html}).attributes[:notes]
    assert_includes notes, "https://www.printables.com/model/92002"
    refute_match(/fictionalSecret|javascript:|data:|user:password|iframe|tracker/, notes)
    [" ", "<p></p>", "<p>&nbsp;</p>", "<script>unsafe()</script>"].each do |description|
      assert_equal({notes: "Fictional fallback"}, Mapper.new({"description" => description, "summary" => "Fictional fallback"}).attributes)
    end
    assert_equal({}, Mapper.new({}).attributes)
    assert_nil Mapper.new({}).creator
  end

  def test_print_images_are_safe_deduplicated_and_keep_primary_identity_after_filename_collisions
    first = "media/prints/92001/first/front_view.jpg"
    primary = "media/prints/92001/second/front%20view.jpg"
    mapper = Mapper.new({"image" => {"filePath" => primary}, "images" => [
      {"filePath" => first}, {"filePath" => primary}, {"filePath" => "media/auth/42/avatar.png"},
      {"filePath" => "https://example.invalid/image.jpg"}, {"filePath" => "media/prints/../secret.jpg"},
      {"filePath" => "media/prints/%2e%2e/secret.jpg"}, {"filePath" => "media/prints/92001/file%00name.jpg"},
      {"filePath" => "media/prints/92001/unsafe.jpg?token=fictional"}, nil],
      "stls" => [{"filePath" => "media/prints/92001/model.stl"}], "downloadUrl" => "https://example.invalid/model.zip"})
    assert_equal %w[images/printables/front_20view.jpg images/printables/front_view.jpg], mapper.file_urls.map { |image| image[:filename] }
    assert_equal 2, mapper.images.size
    assert mapper.images.first[:primary]
    assert_equal "https://media.printables.com/media/prints/92001/second/front%20view.jpg", mapper.images.first[:url]
    refute mapper.file_urls.any? { |file| file[:filename].end_with?(".stl", ".zip") }
    collision = Mapper.new({"image" => {"filePath" => first}, "images" => [{"filePath" => "media/prints/92002/front_view.jpg"}]})
    assert_equal %w[images/printables/front_view.jpg images/printables/front_view_2.jpg], collision.images.map { |image| image[:filename] }
    assert collision.images.first[:primary]
  end

  def test_creator_mapping_preserves_the_raw_validated_user
    user = {"id" => "9001", "handle" => "example-studio", "publicUsername" => "Example Studio", "bio" => nil}
    assert_equal user, Mapper.new({"user" => user}).creator
    [nil, "example", {"publicUsername" => "Example"}, user.merge("handle" => "bad/handle")].each do |invalid|
      assert_nil Mapper.new({"user" => invalid}).creator
    end
  end
end
