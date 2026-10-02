# frozen_string_literal: true

require "faraday"

module ManyfoldPrintables
  class ObjectDeserializer < ::Integrations::BaseDeserializer
    def initialize(uri: nil, payload: nil)
      @payload = payload
      @source = Source.new(payload ? payload.fetch("id") : uri)
      @uri = Source.canonical_url("id" => @source.id)
    rescue Source::Invalid, KeyError
      @source = @uri = nil
    end

    def deserialize
      return {} unless valid?(for_class: ::Model)
      payload = @payload || ApiClient.new.object(@source.id)
      unless payload.is_a?(Hash) && payload["id"].to_s == @source.id
        raise ApiClient::InvalidResponse, "Printables returned an unexpected model."
      end
      mapper = MetadataMapper.new(payload)
      attributes = mapper.attributes.merge(
        file_urls: mapper.file_urls,
        preview_filename: mapper.images.find { |image| image[:primary] }&.dig(:filename)
      )
      if (creator = mapper.creator)
        profile = CreatorSource.from_payload(creator)
        attributes.merge!(attempt_creator_match(CreatorDeserializer.new(uri: profile.uri, payload: creator).deserialize))
      end
      attributes
    rescue ApiClient::Error => error
      raise unless @payload.nil?
      raise Faraday::Error, error.message, cause: nil
    end

    def valid?(for_class: nil)
      ApiClient.configured? && @source.present? && (for_class.nil? || for_class == ::Model)
    end

    def capabilities
      {class: ::Model, name: true, notes: true, tags: true, license: true,
        images: true, model_files: false, sensitive: false, creator: true}
    end
  end
end
