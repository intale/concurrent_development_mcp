# frozen_string_literal: true

module Coordinator::Read::Web::Contracts
  class CoordinationDashboard
    CHANGE_SET_STATUSES = %w[planning active completed].freeze
    PRESENTATION_STATUSES = %w[pending ready assigned running completed].freeze

    class Page < Dry::Validation::Contract
      params do
        required(:project_ref).filled(:string)
        required(:kind).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:after_id).maybe(:string)
        optional(:after_sort_value).maybe(:string)
        optional(:sort).filled(:string, included_in?: Coordinator::Read::Web::CoordinationDashboardQueryV1::LATEST_UPDATE_SORTS)
        optional(:presentation_statuses).array(:string)
        optional(:work_item_sort).filled(:string)
        optional(:blocking).maybe(:bool)
        optional(:domain_status).maybe(:string)
        optional(:change_set_id).maybe(:string)
        optional(:agent_id).maybe(:string)
      end

      rule(:kind) do
        allowed = Coordinator::Read::Web::CoordinationDashboardQueryV1::KINDS
        key.failure("is unsupported") unless allowed.include?(value)
      end

      rule(:presentation_statuses) do
        next unless key?

        valid = value.uniq.length == value.length && (value - PRESENTATION_STATUSES).empty?
        key.failure("contains an unsupported status") unless valid
      end

      rule(:work_item_sort) do
        next unless key?

        allowed = Coordinator::Read::Web::CoordinationDashboardQueryV1::WORK_ITEM_SORTS
        key.failure("is unsupported") unless allowed.include?(value)
      end

      rule(:domain_status) do
        next unless value

        key.failure("is unsupported") unless CHANGE_SET_STATUSES.include?(value)
      end

      rule(:after_id, :after_sort_value, :kind, :work_item_sort) do
        sort = values[:work_item_sort] || "updated_at_desc"
        needs_sort_value = values[:after_id]
        key(:after_sort_value).failure("is required for this cursor") if needs_sort_value && !values[:after_sort_value]
        next unless needs_sort_value && values[:after_sort_value]

        valid = case sort
        when "status_asc"
          values[:after_sort_value].match?(/\A[0-4]\z/)
        when "latest_activity_desc", "updated_at_desc", "updated_at_asc"
          values[:after_sort_value].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/)
        end
        key(:after_sort_value).failure("is invalid for this sort") unless valid
      end
    end

    class Detail < Dry::Validation::Contract
      params do
        required(:project_ref).filled(:string)
        required(:kind).filled(:string)
        required(:id).filled(:string)
      end

      rule(:kind) do
        allowed = Coordinator::Read::Web::CoordinationDashboardQueryV1::KINDS
        key.failure("is unsupported") unless allowed.include?(value)
      end
    end
  end
end
