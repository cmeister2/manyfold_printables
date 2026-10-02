# frozen_string_literal: true

require "uri"

module ManyfoldPrintables
  class Source
    MAX_ID = (2**63) - 1
    HOSTS = %w[printables.com www.printables.com].freeze
    class Invalid < StandardError; end

    attr_reader :id

    def initialize(value)
      text = value.to_s
      unless text.valid_encoding? && text.bytesize.between?(1, 4096)
        raise Invalid, "Enter a Printables model URL or numeric model ID."
      end
      text = text.strip
      raise Invalid, "Enter a Printables model URL or numeric model ID." if text.match?(/[[:cntrl:]]/)
      @id = if positive_id?(text)
        text
      else
        uri = URI.parse(text)
        match = uri.path&.match(%r{\A/(?:[a-z]{2}/)?model/([1-9][0-9]{0,18})(?:-[^/]+)?(?:/(?:files|comments|makes|related))?/?\z})
        match[1] if valid_uri?(uri) && match && positive_id?(match[1])
      end
      raise Invalid, "Enter a Printables model URL or numeric model ID." unless @id
    rescue URI::InvalidURIError, URI::InvalidComponentError
      raise Invalid, "Enter a Printables model URL or numeric model ID.", cause: nil
    end

    def self.canonical_url(payload)
      raise Invalid, "Printables returned an incomplete model." unless payload.is_a?(Hash)
      raise Invalid, "Printables returned an invalid model ID." unless valid_id?(payload["id"])
      source = new(payload.fetch("id"))
      "https://www.printables.com/model/#{source.id}"
    rescue KeyError
      raise Invalid, "Printables returned an incomplete model URL.", cause: nil
    end

    private

    def self.valid_id?(value)
      (value.is_a?(String) || value.is_a?(Integer)) && value.to_s.valid_encoding? &&
        value.to_s.match?(/\A[1-9][0-9]{0,18}\z/) && value.to_i <= MAX_ID
    end

    def positive_id?(value)
      self.class.valid_id?(value)
    end

    def valid_uri?(uri)
      expected_port = {"http" => 80, "https" => 443}[uri.scheme]
      expected_port && uri.port == expected_port && !uri.userinfo && HOSTS.include?(uri.host&.downcase)
    end
  end
end
