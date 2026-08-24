# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class VerificationObligationList < Dry::Validation::Contract
      FILTER_KEYS = %i[
        obligation_id
        change_set_id
        candidate_id
        work_item_id
        repository_id
        kind
        enforcement
        status
        claimant_id
        claim_state
      ].freeze

      config.validate_keys = true

      params do
        optional(:obligation_id).maybe(:string)
        optional(:change_set_id).maybe(:string)
        optional(:candidate_id).maybe(:string)
        optional(:work_item_id).maybe(:string)
        optional(:repository_id).maybe(:string)
        optional(:kind).maybe(:string, included_in?: Types::VERIFICATION_OBLIGATION_KINDS)
        optional(:enforcement).maybe(
          :string,
          included_in?: %w[verification_gate merge_gate]
        )
        optional(:status).maybe(:string, included_in?: Types::VERIFICATION_OBLIGATION_STATUSES)
        optional(:claimant_id).maybe(:string)
        optional(:claim_state).maybe(
          :string,
          included_in?: Types::VERIFICATION_OBLIGATION_CLAIM_STATES
        )
        optional(:after_global_position).maybe(:integer, gteq?: 0)
        optional(:limit).maybe(:integer, gteq?: 1, lteq?: 100)
      end

      rule do
        key(:change_set_id).failure("at least one obligation filter is required") unless FILTER_KEYS.any? do |filter|
          values[filter]
        end
      end

      rule(:obligation_id, :change_set_id, :candidate_id, :work_item_id, :claimant_id) do
        identifiers = values.values_at(
          :obligation_id,
          :change_set_id,
          :candidate_id,
          :work_item_id,
          :claimant_id
        ).compact
        next if identifiers.all? { Types::IDENTIFIER_PATTERN.match?(_1) }

        key.failure("must contain valid identifiers")
      end

      rule(:repository_id) do
        next unless value
        next if Types::REPOSITORY_ID_PATTERN.match?(value)

        key.failure("must be a valid repository ID")
      end
    end
  end
end
