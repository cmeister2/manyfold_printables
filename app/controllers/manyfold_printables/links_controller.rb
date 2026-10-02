# frozen_string_literal: true

module ManyfoldPrintables
  class LinksController < ::ApplicationController
    before_action :load_model
    protect_from_forgery with: :exception

    def new
      @source = params.permit(:source)[:source].to_s
      prepare_form
    end

    def create
      @source = params.permit(:source)[:source].to_s
      source = Source.new(@source)
      unless ApiClient.configured?
        raise ApiClient::ConfigurationError, "Enable Printables in integration settings first."
      end

      SyncJob.perform_later(@model.id, current_user.id, source.id)
      redirect_to main_app.model_path(@model), notice: "Printables sync is queued.", status: :see_other
    rescue Source::Invalid, ApiClient::Error => error
      @error = error.message
      prepare_form
      render :new, status: :unprocessable_content
    end

    private

    def load_model
      authorize :settings, :integrations?
      @model = policy_scope(::Model).find_param(params.permit(:model_id)[:model_id])
      authorize @model, :sync?
    end

    def prepare_form
      @match_query = (params.key?(:match_q) ? params.permit(:match_q)[:match_q] : @model.name).to_s.strip.slice(0, 200)
      @configured = ApiClient.configured?
      @matches = []
      return unless @configured && @match_query.present?
      search_query = ModelMatcher.new([]).search_query(@match_query)
      return if search_query.blank?

      items = ApiClient.new.search(search_query, limit: 20).map do |item|
        {"id" => Integer(item.fetch("id").to_s, 10), "name" => item.fetch("name"),
         "creator_name" => item.dig("user", "publicUsername").to_s}
      end
      @matches = ModelMatcher.new(items)
        .matches(name: @match_query, creator: @model.creator&.name, limit: 5)
    rescue ApiClient::Error, ModelMatcher::Error => error
      @match_error = error.message
    end
  end
end
