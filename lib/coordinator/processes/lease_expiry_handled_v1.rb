# frozen_string_literal: true

module Coordinator::Processes
  class LeaseExpiryHandledV1 < Value
    OUTCOMES = %w[
      expired_or_replayed
      lease_observation_superseded
      lease_released
      lease_already_expired
      legacy_source_ignored
    ].freeze

    attribute :outcome, Types::String.enum(*OUTCOMES)
  end
end
