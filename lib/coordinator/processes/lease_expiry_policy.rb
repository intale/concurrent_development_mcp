# frozen_string_literal: true

module Coordinator::Processes
  class LeaseExpiryPolicy
    include Dry::Monads[:result]

    HANDLED_OUTCOME_CODES = %i[
      lease_observation_superseded
      lease_released
      lease_already_expired
    ].freeze

    def initialize(
      source_loader:,
      command_builder: LeaseExpiryCommandBuilder.new,
      operation:
    )
      @source_loader = source_loader
      @command_builder = command_builder
      @operation = operation
    end

    def call(locator)
      source = @source_loader.call(locator)
      command = @command_builder.call(source)
      result = @operation.call(command, caused_by: source.event)
      return Success(LeaseExpiryHandledV1.new(outcome: "expired_or_replayed")) if result.success?

      map_failure(result.failure)
    end

    private

    def map_failure(error)
      if error.code == :lease_deadline_not_reached
        return Success(
          LeaseExpiryRescheduleV1.new(
            reschedule_at: error.details.fetch(:expected_expires_at)
          )
        )
      end
      if HANDLED_OUTCOME_CODES.include?(error.code)
        return Success(LeaseExpiryHandledV1.new(outcome: error.code.to_s))
      end

      Failure(error)
    end
  end
end
