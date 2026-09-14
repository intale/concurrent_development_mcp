# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module WorkIntentions
      class RenewSet
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(attempt_state:, set_state:, member_states:, command:, renewed_at:, expires_at:)
          denial = denied(
            attempt_state:,
            set_state:,
            member_states:,
            command:,
            renewed_at:
          )
          return denial if denial

          extending = member_states.select { expires_at > _1.expires_at }
          return Success(WorkIntentionDecisionV1.no_change) if extending.empty?

          writes = extending.map do |state|
            EventWrite.new(
              stream: @stream_factory.resource_work_intention(state.intention_id),
              event: Events::ResourceWorkIntentionRenewedV1.new(
                intention_id: state.intention_id,
                resource_id: state.resource_id,
                fencing_token: state.fencing_token,
                expires_at:
              )
            )
          end
          Success(WorkIntentionDecisionV1.write(EventPlan.new(writes:)))
        end

        private

        def denied(attempt_state:, set_state:, member_states:, command:, renewed_at:)
          scope_denial = scope_denied(attempt_state:, set_state:, command:)
          return scope_denial if scope_denial

          current_by_resource = member_states.to_h { [ _1.resource_id, _1 ] }
          requested_ids = command.leases.map(&:resource_id)
          current_ids = set_state.members.map(&:resource_id)
          unless requested_ids.sort_by(&:b) == current_ids.sort_by(&:b)
            return failure(
              :work_intention_set_snapshot_mismatch,
              "Submitted members do not equal the work-intention set",
              command,
              current_resource_ids: current_ids,
              requested_resource_ids: requested_ids
            )
          end

          mismatch = command.leases.find do |reference|
            state = current_by_resource[reference.resource_id]
            state.nil? || state.intention_id != reference.lease_id || state.fencing_token != reference.fencing_token
          end
          if mismatch
            state = current_by_resource[mismatch.resource_id]
            return failure(
              :work_intention_reference_mismatch,
              "Submitted work-intention identity or fencing token is stale",
              command,
              resource_id: mismatch.resource_id,
              current_intention_id: state&.intention_id,
              requested_intention_id: mismatch.lease_id,
              current_fencing_token: state&.fencing_token || 0,
              requested_fencing_token: mismatch.fencing_token
            )
          end

          inactive = member_states.find { !_1.active_at?(renewed_at) }
          return unless inactive

          failure(
            :work_intention_set_inactive,
            "The work-intention set contains an inactive member",
            command,
            resource_id: inactive.resource_id,
            intention_id: inactive.intention_id,
            fencing_token: inactive.fencing_token,
            expires_at: inactive.expires_at
          )
        end

        def scope_denied(attempt_state:, set_state:, command:)
          return failure(:attempt_not_found, "Attempt does not exist", command) if attempt_state.absent?
          return failure(:attempt_not_active, "Attempt is not active", command) unless attempt_state.status == "active"
          unless attempt_state.change_set_id == command.change_set_id &&
                 attempt_state.work_item_id == command.work_item_id
            return failure(:attempt_scope_mismatch, "Attempt does not belong to the requested scope", command)
          end
          unless attempt_state.agent_id == command.actor.id
            return failure(:attempt_owner_mismatch, "Attempt belongs to another agent attribution", command)
          end
          return failure(:work_intention_set_missing, "Attempt has no work-intention set", command) if set_state.absent?
          unless set_state.set_id == command.lease_set_id
            return failure(
              :work_intention_set_mismatch,
              "Work-intention set ID does not match",
              command,
              current_intention_set_id: set_state.set_id,
              requested_intention_set_id: command.lease_set_id
            )
          end
          return if set_state.attempt_id == command.attempt_id &&
                    set_state.work_item_id == command.work_item_id &&
                    set_state.change_set_id == command.change_set_id

          failure(:attempt_scope_mismatch, "Work-intention set belongs to another scope", command)
        end

        def failure(code, message, command, **extra_details)
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: {
                change_set_id: command.change_set_id,
                work_item_id: command.work_item_id,
                attempt_id: command.attempt_id
              }.merge(extra_details)
            )
          )
        end
      end
    end
  end
end
