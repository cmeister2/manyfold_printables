# frozen_string_literal: true

require "uri"

module ManyfoldPrintables
  # Register both model and creator profiles with Manyfold's native link factory.
  module CreatorLinks
    def self.install!
      ::Link.singleton_class.prepend(DeserializerFactory) unless ::Link.singleton_class < DeserializerFactory
    end

    module DeserializerFactory
      def deserializer_for(url:, for_class: nil)
        return super unless printables_provider_url?(url)

        if for_class.nil? || for_class == ::Creator
          deserializer = CreatorDeserializer.new(uri: url)
          return deserializer if deserializer.valid?(for_class: for_class)
        end
        if for_class.nil? || for_class == ::Model
          deserializer = ObjectDeserializer.new(uri: url)
          return deserializer if deserializer.valid?(for_class: for_class)
        end
        super
      end

      private

      def printables_provider_url?(value)
        CreatorSource.valid_uri?(URI.parse(value.to_s.strip))
      rescue URI::InvalidURIError, URI::InvalidComponentError, ArgumentError
        false
      end
    end
  end
end
