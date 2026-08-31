# frozen_string_literal: true

module Coordinator::Read::Web::Contracts
  class CoordinationDashboard < Dry::Validation::Contract
    params do
      required(:repository_id).filled(:string)
      optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
      optional(:change_set_offset).filled(:integer, gteq?: 0)
      optional(:work_item_offset).filled(:integer, gteq?: 0)
      optional(:dependency_offset).filled(:integer, gteq?: 0)
      optional(:presentation_statuses).array(:string)
      optional(:work_item_sort).filled(:string)
      optional(:blocking).maybe(:bool)
    end

    rule(:repository_id) do
      key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
    end

    rule(:presentation_statuses) do
      next unless key?

      allowed = %w[pending ready assigned running completed]
      key.failure("contains an unsupported status") unless value.uniq.length == value.length && (value - allowed).empty?
    end

    rule(:work_item_sort) do
      next unless key?

      allowed = %w[work_item_id_asc status_asc latest_activity_desc]
      key.failure("is unsupported") unless allowed.include?(value)
    end
  end
end
