# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module WorkIntentions
      class Expire
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, observed_at:)
          return failure(:lease_not_found, "Work intention does not exist", command, state) if state.absent?
          return Success(WorkIntentionDecisionV1.no_change) unless exact_observation?(state:, command:)
          return Success(WorkIntentionDecisionV1.no_change) if state.withdrawn || state.expired
          if observed_at < state.expires_at
            return failure(
              :lease_deadline_not_reached,
              "Work intention has not reached its expiry deadline",
              command,
              state
            )
          end

          event = Events::ResourceWorkIntentionExpiredV1.new(
            intention_id: state.intention_id,
            resource_id: state.resource_id,
            fencing_token: state.fencing_token,
            expires_at: state.expires_at
          )
          plan = EventPlan.new(
            writes: [
              EventWrite.new(
                stream: @stream_factory.resource_work_intention(state.intention_id),
                event:
              )
            ]
          )
          Success(WorkIntentionDecisionV1.write(plan))
        end

        private

        def exact_observation?(state:, command:)
          state.resource_id == command.resource_id &&
            state.intention_id == command.lease_id &&
            state.set_id == command.lease_set_id &&
            state.fencing_token == command.fencing_token &&
            state.expires_at == command.expected_expires_at
        end

        def failure(code, message, command, state)
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: {
                resource_id: command.resource_id,
                expected_lease_id: command.lease_id,
                current_lease_id: state.intention_id,
                expected_lease_set_id: command.lease_set_id,
                current_lease_set_id: state.set_id,
                expected_fencing_token: command.fencing_token,
                current_fencing_token: state.fencing_token,
                expected_expires_at: command.expected_expires_at,
                current_expires_at: state.expires_at,
                current_released_at: state.withdrawn ? state.expires_at : nil,
                current_expired_at: state.expired ? state.expires_at : nil
              }
            )
          )
        end
      end
    end
  end
end
