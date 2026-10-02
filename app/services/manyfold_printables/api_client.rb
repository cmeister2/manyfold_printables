# frozen_string_literal: true

require "faraday"
require "json"

module ManyfoldPrintables
  class ApiClient
    BASE_URL = "https://api.printables.com/graphql/"
    USER_FIELDS = "id handle publicUsername avatarFilePath bannerFilePath bio"
    MODEL_FIELDS = <<~GRAPHQL.freeze
      id name slug description summary datePublished
      tags { name } license { id name }
      image { filePath } images { filePath }
      user { #{USER_FIELDS} }
    GRAPHQL
    OBJECT_QUERY = <<~GRAPHQL.freeze
      query Model($id: ID!) { print(id: $id) { #{MODEL_FIELDS} } }
    GRAPHQL
    CREATOR_QUERY = <<~GRAPHQL.freeze
      query Creator($id: ID!) { user(id: $id) { #{USER_FIELDS} } }
    GRAPHQL
    SEARCH_QUERY = <<~GRAPHQL.freeze
      query Search($query: String!, $limit: Int!) {
        searchPrints2(query: $query, limit: $limit, ordering: best_match) {
          items { id name user { publicUsername } }
        }
      }
    GRAPHQL
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class InvalidObjectId < Error; end
    class AuthenticationError < Error; end
    class NotFound < Error; end
    class RateLimited < Error; end
    class Unavailable < Error; end
    class InvalidResponse < Error; end
    class InvalidSearch < Error; end

    def self.configured?
      SiteSettings.printables_enabled
    end

    def initialize(connection: nil)
      @connection = connection
    end

    def object(id)
      unless Source.valid_id?(id)
        raise InvalidObjectId, "Enter a positive Printables model ID."
      end
      source = Source.new(id)
      payload = request(OBJECT_QUERY, {id: source.id})["print"]
      raise NotFound, "Printables could not find that model." if payload.nil?
      invalid! unless payload.is_a?(Hash) && payload["id"].to_s == source.id && payload["name"].is_a?(String)
      payload
    rescue Source::Invalid
      raise InvalidObjectId, "Enter a Printables model URL or numeric model ID.", cause: nil
    end

    def creator(handle)
      unless CreatorSource.valid_username?(handle)
        raise InvalidObjectId, "Enter a Printables creator handle."
      end
      payload = request(CREATOR_QUERY, {id: "@#{handle}"})["user"]
      raise NotFound, "Printables could not find that creator." if payload.nil?
      invalid! unless CreatorSource.new(CreatorSource.profile_url(handle)).matches?(payload)
      payload
    end

    def search(query, limit: 20)
      unless query.is_a?(String) && query.valid_encoding? && query.bytesize <= 1024 &&
          !query.match?(/[[:cntrl:]]/) && limit.is_a?(Integer) && limit.between?(1, 20)
        raise InvalidSearch, "Enter a Printables search without control characters, up to 200 characters."
      end
      text = query.strip
      raise InvalidSearch, "Enter a Printables search up to 200 characters." if text.length > 200
      return [] if text.empty?

      batch = request(SEARCH_QUERY, {query: text, limit: limit})["searchPrints2"]
      invalid! unless batch.is_a?(Hash) && batch["items"].is_a?(Array) && batch["items"].length <= limit
      batch["items"].each do |item|
        invalid! unless item.is_a?(Hash) && Source.valid_id?(item["id"]) &&
          item["name"].is_a?(String) && item["name"].valid_encoding? &&
          (item["user"].nil? || item["user"].is_a?(Hash))
      end
      batch["items"]
    end

    private

    def request(query, variables)
      headers = {"Accept" => "application/json", "Content-Type" => "application/json",
        "User-Agent" => "ManyfoldPrintables (personal library integration)"}
      response = connection.post(BASE_URL, JSON.generate(query: query, variables: variables), headers)
      check_status!(response.status)
      payload = response.body
      invalid! unless payload.is_a?(Hash)
      if payload.key?("errors")
        invalid! unless payload["errors"].is_a?(Array)
        unless payload["errors"].empty?
          if payload["errors"].any? { |error| error.is_a?(Hash) && error["message"] == "user_is_not_authenticated" }
            raise AuthenticationError, "Printables denied access to that model or creator. Choose a publicly available item."
          end
          invalid!
        end
      end
      invalid! unless payload["data"].is_a?(Hash)
      payload["data"]
    rescue Faraday::ParsingError
      raise InvalidResponse, "Printables returned an unreadable response.", cause: nil
    rescue Faraday::Error
      raise Unavailable, "Printables could not be reached. Try again later.", cause: nil
    end

    def connection
      @connection ||= Faraday.new do |builder|
        builder.options.open_timeout = 5
        builder.options.timeout = 30
        builder.response :json
      end
    end

    def invalid!
      raise InvalidResponse, "Printables returned incomplete or unexpected data. Try again later."
    end

    def check_status!(status)
      case status
      when 200
        nil
      when 401, 403
        raise AuthenticationError, "Printables denied access to that model or creator. Choose a publicly available item."
      when 404
        raise NotFound, "Printables could not find that model."
      when 429
        raise RateLimited, "Printables is limiting requests. Try again later."
      when 400
        invalid!
      else
        raise Unavailable, "Printables could not complete the request. Try again later."
      end
    end
  end
end
