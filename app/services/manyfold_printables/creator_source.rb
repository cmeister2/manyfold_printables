# frozen_string_literal: true

require "uri"

module ManyfoldPrintables
  class CreatorSource
    MAX_USERNAME_BYTES = 512
    PROFILE_PATH = %r{\A/(?:[a-z]{2}/)?@([^/]+)(?:/(?:models|collections|makes|club))?/?\z}
    MESSAGE = "Enter a Printables creator profile URL."

    class Invalid < StandardError; end

    attr_reader :uri, :username, :id

    def initialize(value, id: nil)
      text = value.to_s
      unless text.valid_encoding? && text.bytesize.between?(1, 4096) && !text.match?(/[[:cntrl:]]/)
        raise Invalid, MESSAGE
      end

      parsed = URI.parse(text.strip)
      raise Invalid, MESSAGE unless self.class.valid_uri?(parsed)
      match = parsed.path.match(PROFILE_PATH)
      raise Invalid, MESSAGE unless match

      @username = URI::DEFAULT_PARSER.unescape(match[1]).force_encoding(Encoding::UTF_8)
      raise Invalid, MESSAGE unless self.class.valid_username?(@username)
      raise Invalid, MESSAGE if id && !self.class.valid_id?(id)

      @id = id&.to_s
      @uri = self.class.profile_url(@username)
    rescue URI::InvalidURIError, URI::InvalidComponentError, ArgumentError
      raise Invalid, MESSAGE, cause: nil
    end

    def matches?(payload)
      other = self.class.from_payload(payload)
      username.casecmp?(other.username) && (id.nil? || id == other.id)
    rescue Invalid
      false
    end

    def self.from_payload(payload)
      unless payload.is_a?(Hash) && valid_username?(payload["handle"]) && valid_id?(payload["id"])
        raise Invalid, "Printables returned an incomplete creator profile."
      end

      new(profile_url(payload["handle"]), id: payload["id"])
    end

    def self.linked?(creator)
      creator.links.any? do |link|
        new(link.url)
        true
      rescue Invalid
        false
      end
    end

    def self.valid_username?(value)
      value.is_a?(String) && value.valid_encoding? && value.bytesize.between?(1, MAX_USERNAME_BYTES) &&
        value.match?(/\A[[:alnum:]_.-]+\z/) && value.parameterize.present?
    end

    def self.valid_id?(value)
      Source.valid_id?(value)
    end

    def self.valid_uri?(value)
      (value.is_a?(URI::HTTPS) && value.port == 443 || value.is_a?(URI::HTTP) && value.scheme == "http" && value.port == 80) &&
        !value.userinfo && Source::HOSTS.include?(value.host&.downcase)
    end

    def self.profile_url(username)
      "https://www.printables.com/@#{URI.encode_www_form_component(username).gsub('+', '%20')}"
    end
  end
end
