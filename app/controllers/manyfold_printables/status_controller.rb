# frozen_string_literal: true

module ManyfoldPrintables
  class StatusController < ::ApplicationController
    def index
      # This page shows configuration only, without listing scoped records.
      skip_policy_scope
      @linked = ApiClient.configured?
    end
  end
end
