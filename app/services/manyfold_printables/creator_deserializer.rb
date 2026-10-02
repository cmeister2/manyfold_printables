# frozen_string_literal: true

require "faraday"

module ManyfoldPrintables
  class CreatorDeserializer < ::Integrations::BaseDeserializer
    def initialize(uri:, payload: nil)
      @payload = payload
      @source = CreatorSource.new(uri)
      @uri = @source.uri
    rescue CreatorSource::Invalid
      @source = @uri = nil
    end

    def deserialize
      return {} unless valid?

      payload = @payload.nil? ? ApiClient.new.creator(@source.username) : @payload
      unless @source.matches?(payload)
        raise ApiClient::InvalidResponse, "Printables returned an unexpected creator profile."
      end
      source = CreatorSource.from_payload(payload)
      attributes = {
        name: text(payload["publicUsername"]) || source.username,
        slug: source.username.parameterize,
        links_attributes: [{url: source.uri}]
      }
      bio = payload["bio"]
      if bio.is_a?(String) && bio.valid_encoding?
        attributes[:notes] = MetadataMapper.markdown(bio.strip, base_url: source.uri)
      end
      avatar = MetadataMapper.media_url(payload["avatarFilePath"])
      banner = MetadataMapper.media_url(payload["bannerFilePath"])
      attributes[:avatar_remote_url] = avatar if avatar
      attributes[:banner_remote_url] = banner if banner
      attributes
    rescue ApiClient::Error => error
      raise unless @payload.nil?

      # Native Manyfold sync jobs report Faraday errors against the profile link.
      raise Faraday::Error, error.message, cause: nil
    end

    def valid?(for_class: nil)
      ApiClient.configured? && @source.present? && (for_class.nil? || for_class == ::Creator)
    end

    def capabilities
      {class: ::Creator, name: true, slug: true, notes: true}
    end

    private

    def text(value)
      return unless value.is_a?(String) && value.valid_encoding?
      normalized = value.strip
      normalized unless normalized.empty?
    end
  end
end
