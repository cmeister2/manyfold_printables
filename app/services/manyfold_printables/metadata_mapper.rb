# frozen_string_literal: true

require "cgi"
require "uri"
require "nokogiri"
require "reverse_markdown"

module ManyfoldPrintables
  class MetadataMapper
    IMAGE_DIRECTORY = "images/printables/"
    MAX_BASENAME_BYTES = 255 - IMAGE_DIRECTORY.bytesize
    LICENSES = {
      "7" => "CC0-1.0",
      "1" => "CC-BY-4.0",
      "2" => "CC-BY-SA-4.0",
      "8" => "CC-BY-ND-4.0",
      "3" => "CC-BY-NC-4.0",
      "4" => "CC-BY-NC-SA-4.0",
      "6" => "CC-BY-NC-ND-4.0"
    }.freeze

    def initialize(payload)
      @payload = payload
    end

    def attributes
      {
        name: text(@payload["name"]),
        notes: description,
        tag_list: tags,
        license: license
      }.reject { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
    end

    def creator
      payload = @payload["user"]
      CreatorSource.from_payload(payload)
      payload
    rescue CreatorSource::Invalid
      nil
    end

    def images
      primary = @payload["image"].is_a?(Hash) ? @payload["image"]["filePath"] : nil
      paths = [primary, *Array(@payload["images"]).filter_map { |image| image["filePath"] if image.is_a?(Hash) }].compact.uniq
      descriptors = paths.filter_map do |path|
        url = self.class.media_url(path, prefix: "media/prints/")
        next unless url
        filename = File.basename(URI.parse(url).path).gsub(/[^a-zA-Z0-9._-]/, "_").sub(/\A\.+/, "")
        next if filename.empty?
        {url: url, filename: filename, primary: path == primary}
      end
      unique_filenames(descriptors)
    end

    def file_urls
      images.map { |image| image.slice(:url, :filename) }
    end

    def self.media_url(value, prefix: "media/")
      return unless value.is_a?(String) && value.valid_encoding? && value.bytesize <= 4096
      decoded = URI::DEFAULT_PARSER.unescape(value).force_encoding(Encoding::UTF_8)
      return unless decoded.valid_encoding? && decoded.start_with?(prefix) &&
        !decoded.match?(/[[:cntrl:]\\?#]/) && (decoded.split("/") & [".", ".."]).empty? &&
        !decoded.end_with?("/")
      "https://media.printables.com/#{URI::DEFAULT_PARSER.escape(decoded)}"
    end

    def self.markdown(html, base_url: "https://www.printables.com/")
      return unless html.is_a?(String) && html.valid_encoding? && html.present?
      fragment = Nokogiri::HTML.fragment(html)
      fragment.css("script, style, iframe, object, embed, form").remove
      fragment.css("a[href], img[src]").each do |node|
        attribute = node.name == "a" ? "href" : "src"
        uri = URI.join(base_url, node[attribute]) rescue nil
        if uri && %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo
          node[attribute] = uri.to_s
        else
          node.remove_attribute(attribute)
        end
      end
      return if fragment.text.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "").empty? && fragment.css("img[src]").empty?
      ReverseMarkdown.convert(fragment.to_html, unknown_tags: :drop).strip.presence
    end

    private

    def text(value)
      return unless value.is_a?(String) && value.valid_encoding?
      value.strip.presence
    end

    def description
      self.class.markdown(@payload["description"], base_url: Source.canonical_url(@payload)) || text(@payload["summary"])
    rescue Source::Invalid
      self.class.markdown(@payload["description"]) || text(@payload["summary"])
    end

    def tags
      return [] unless @payload["tags"].is_a?(Array)
      @payload["tags"].filter_map { |tag| text(tag["name"]) if tag.is_a?(Hash) }.uniq
    end

    def license
      raw = @payload["license"]
      LICENSES[raw["id"].to_s] if raw.is_a?(Hash)
    end

    def unique_filenames(descriptors)
      used = {}
      next_suffix = {}
      descriptors.map do |descriptor|
        filename = descriptor[:filename]
        candidate = bounded_filename(filename)
        key = candidate.downcase
        index = next_suffix.fetch(key, 2)
        while used[candidate.downcase]
          candidate = bounded_filename(filename, suffix: "_#{index}")
          index += 1
        end
        next_suffix[key] = index
        used[candidate.downcase] = true
        descriptor.merge(filename: "#{IMAGE_DIRECTORY}#{candidate}")
      end
    end

    def bounded_filename(filename, suffix: "")
      extension = File.extname(filename)
      if extension.bytesize + suffix.bytesize >= MAX_BASENAME_BYTES
        extension = extension.byteslice(0, MAX_BASENAME_BYTES - suffix.bytesize - 1).scrub("")
      end
      stem = File.basename(filename, File.extname(filename))
        .byteslice(0, MAX_BASENAME_BYTES - extension.bytesize - suffix.bytesize).scrub("")
      "#{stem.empty? ? '_' : stem}#{suffix}#{extension}"
    end
  end
end
