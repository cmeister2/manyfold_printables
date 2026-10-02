# frozen_string_literal: true

module ManyfoldPrintables
  class SyncJob < ::UpdateMetadataFromLinkJob
    def perform(model_id, user_id, object_id)
      return unless ApiClient.configured?

      model = ::Model.find(model_id)
      user = ::User.find(user_id)
      return unless user.is_administrator? && ::ModelPolicy.new(user, model).sync?

      id = Source.new(object_id).id
      payload = ApiClient.new.object(id)
      unless payload.is_a?(Hash) && payload["id"].to_s == id
        raise ApiClient::InvalidResponse, "Printables returned an unexpected model."
      end
      deserializer = ObjectDeserializer.new(payload: payload)
      link = model.links.find_or_create_by!(url: deserializer.uri)
      link.define_singleton_method(:deserializer) { deserializer }
      status.update(model_id: model.id, object_id: id)
      super(link: link, organize: false)
    rescue ApiClient::Error, Source::Invalid => error
      status.update(error: "manyfold_printables.errors.request_failed", printables_message: error.message)
    rescue ActiveRecord::RecordInvalid => error
      status.update(error: "manyfold_printables.errors.sync_failed", printables_message: error.message)
    end
  end
end
