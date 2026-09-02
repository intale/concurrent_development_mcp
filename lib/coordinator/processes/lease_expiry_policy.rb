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
      event_store:,
      source_loader:,
      command_builder: LeaseExpiryCommandBuilder.new,
      process_step_planner: ProcessStepPlanner.new(event_store:),
      operation:
    )
      @source_loader = source_loader
      @command_builder = command_builder
      @process_step_planner = process_step_planner
      @operation = operation
    end

    def call(locator)
      source = @source_loader.call(locator)
      process_step = @process_step_planner.call(
        source_event: source.event,
        process_name: "lease-expiry-policy",
        step_name: "expire-resource-lease",
        subject_kind: "resource-lease",
        subject_id: source.payload.lease_id,
        rule_version: "lease-expiry/v1",
        allocate_target_entity: false
      )
      command = @command_builder.call(source, command_id: process_step.target_command_id)
      result = @operation.call(command, caused_by: process_step.event)
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
