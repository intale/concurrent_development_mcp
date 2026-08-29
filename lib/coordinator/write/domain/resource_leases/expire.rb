# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ResourceLeases
      class Expire
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, expired_at:)
          denial = denied(state:, command:, expired_at:)
          return denial if denial

          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.resource_lease(command.resource_id),
                  event: build_expiration(state:, expired_at:)
                )
              ]
            )
          )
        end

        private

        def denied(state:, command:, expired_at:)
          return failure(:lease_not_found, "Resource lease does not exist", command, state) unless state.lease_id

          unless exact_observation?(state:, command:)
            return failure(
              :lease_observation_superseded,
              "The scheduled lease observation is no longer current",
              command,
              state
            )
          end
          if state.released_at
            return failure(:lease_released, "Resource lease was released", command, state)
          end
          if state.expired_at
            return failure(:lease_already_expired, "Resource lease was already explicitly expired", command, state)
          end
          return unless expired_at < command.expected_expires_at

          failure(
            :lease_deadline_not_reached,
            "Resource lease deadline has not been reached",
            command,
            state
          )
        end

        def exact_observation?(state:, command:)
          state.resource_id == command.resource_id &&
            state.lease_id == command.lease_id &&
            state.lease_set_id == command.lease_set_id &&
            state.fencing_token == command.fencing_token &&
            state.expires_at == command.expected_expires_at
        end

        def build_expiration(state:, expired_at:)
          Events::ResourceLeaseExpiredV2.new(
            lease_id: state.lease_id,
            lease_set_id: state.lease_set_id,
            resource_id: state.resource_id,
            resource_kind: state.resource_kind,
            resource_path: state.resource_path,
            policy_version: state.policy_version,
            mode: state.mode,
            change_set_id: state.change_set_id,
            work_item_id: state.work_item_id,
            attempt_id: state.attempt_id,
            agent_id: state.agent_id,
            repository_id: state.repository_id,
            object_format: state.object_format,
            base_commit_oid: state.base_commit_oid,
            base_blob_oid: state.base_blob_oid,
            fencing_token: state.fencing_token,
            acquired_at: state.acquired_at,
            renewed_at: state.renewed_at,
            expires_at: state.expires_at,
            expired_at:
          )
        end

        def failure(code, message, command, state)
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: {
                resource_id: command.resource_id,
                expected_lease_id: command.lease_id,
                current_lease_id: state.lease_id,
                expected_lease_set_id: command.lease_set_id,
                current_lease_set_id: state.lease_set_id,
                expected_fencing_token: command.fencing_token,
                current_fencing_token: state.fencing_token,
                expected_expires_at: command.expected_expires_at,
                current_expires_at: state.expires_at,
                current_released_at: state.released_at,
                current_expired_at: state.expired_at
              }
            )
          )
        end
      end
    end
  end
end
