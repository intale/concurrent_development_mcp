# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module WorkIntentions
      class ExpandSet
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new, conflict_detector: ConflictDetector.new)
          @stream_factory = stream_factory
          @conflict_detector = conflict_detector
        end

        def call(
          attempt_state:,
          set_state:,
          member_states:,
          boundary:,
          command:,
          requests:,
          expanded_at:
        )
          denial = denied(
            attempt_state:,
            set_state:,
            member_states:,
            command:,
            requests:,
            expanded_at:
          )
          return denial if denial

          additions = requests.reject do |request|
            set_state.members.any? { _1.resource_id == request.resource.resource_id }
          end
          if additions.empty?
            return failure(
              :write_set_unchanged,
              "Every requested resource is already in the work-intention set",
              command
            )
          end
          if set_state.members.length + additions.length > WorkIntentionPolicyV1::MAXIMUM_SET_SIZE
            return failure(
              :write_set_limit_reached,
              "The expanded work-intention set would exceed 32 resources",
              command,
              current_resource_count: set_state.members.length,
              requested_addition_count: additions.length
            )
          end

          blockers = @conflict_detector.call(
            requests: additions,
            observations: boundary.active_observations,
            at: expanded_at,
            ignored_intention_ids: set_state.members.map(&:intention_id)
          )
          return conflict(blockers) unless blockers.empty?

          expires_at = member_states.map(&:expires_at).min
          Success(
            WorkIntentionDecisionV1.write(
              build_plan(
                attempt_state:,
                set_state:,
                boundary:,
                command:,
                requests: additions,
                expires_at:
              )
            )
          )
        end

        private

        def denied(attempt_state:, set_state:, member_states:, command:, requests:, expanded_at:)
          scope_denial = scope_denied(attempt_state:, set_state:, command:)
          return scope_denial if scope_denial

          stale = set_state.members.find do |reference|
            state = member_states.find { _1.intention_id == reference.intention_id }
            state.nil? || state.resource_id != reference.resource_id || !state.active_at?(expanded_at)
          end
          if stale
            return failure(
              :lease_set_expired,
              "The work-intention set contains an inactive member",
              command,
              resource_id: stale.resource_id,
              lease_id: stale.intention_id,
              fencing_token: member_states.find { _1.intention_id == stale.intention_id }&.fencing_token || 0,
              expires_at: member_states.find { _1.intention_id == stale.intention_id }&.expires_at || expanded_at
            )
          end

          existing_by_resource = member_states.to_h { [ _1.resource_id, _1 ] }
          mismatch = requests.find do |request|
            current = existing_by_resource[request.resource.resource_id]
            current && current.base_blob_oid != request.resource.base_blob_oid
          end
          return unless mismatch

          current = existing_by_resource.fetch(mismatch.resource.resource_id)
          failure(
            :resource_evidence_conflict,
            "Requested base evidence differs from the current work intention",
            command,
            resource_id: current.resource_id,
            current_base_blob_oid: current.base_blob_oid,
            requested_base_blob_oid: mismatch.resource.base_blob_oid
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
          return failure(:write_set_not_reserved, "Attempt has no work-intention set", command) if set_state.absent?
          unless set_state.set_id == command.lease_set_id
            return failure(
              :lease_set_mismatch,
              "Work-intention set ID does not match",
              command,
              current_lease_set_id: set_state.set_id,
              requested_lease_set_id: command.lease_set_id
            )
          end
          unless set_state.attempt_id == command.attempt_id &&
                 set_state.work_item_id == command.work_item_id &&
                 set_state.change_set_id == command.change_set_id &&
                 set_state.repository_id == command.repository_id
            return failure(:attempt_scope_mismatch, "Work-intention set belongs to another scope", command)
          end

          snapshot = attempt_state.base_snapshots.first
          return if snapshot&.repository_id == command.repository_id && snapshot&.commit_oid == command.base_commit_oid

          failure(:repository_base_mismatch, "Repository base does not match the Attempt", command)
        end

        def build_plan(attempt_state:, set_state:, boundary:, command:, requests:, expires_at:)
          snapshot = attempt_state.base_snapshots.first
          writes = requests.flat_map do |request|
            target = request.prepared_target.target
            resource = request.resource
            intention_id = request.prepared_target.intention_id
            declaration = Events::ResourceWorkIntentionDeclaredV1.new(
              intention_id:,
              set_id: set_state.set_id,
              resource_id: resource.resource_id,
              repository_id: command.repository_id,
              change_set_id: command.change_set_id,
              work_item_id: command.work_item_id,
              attempt_id: command.attempt_id,
              agent_id: command.actor.id,
              mode: target.mode,
              purpose: target.purpose,
              context: target.context,
              object_format: snapshot.object_format,
              base_commit_oid: command.base_commit_oid,
              base_blob_oid: resource.base_blob_oid,
              fencing_token: next_fencing_token(boundary.states, resource.resource_id),
              expires_at:
            )
            membership = Events::WorkIntentionAddedToSetV1.new(
              set_id: set_state.set_id,
              intention_id:,
              resource_id: resource.resource_id
            )
            [
              EventWrite.new(
                stream: @stream_factory.resource_work_intention(intention_id),
                event: declaration
              ),
              EventWrite.new(
                stream: @stream_factory.work_intention_set(set_state.set_id),
                event: membership
              )
            ]
          end
          EventPlan.new(writes:)
        end

        def next_fencing_token(states, resource_id)
          states.select { _1.resource_id == resource_id }.map(&:fencing_token).max.to_i + 1
        end

        def conflict(blockers)
          Failure(
            OutcomeError.new(
              code: :work_intention_conflict,
              message: "A requested work intention conflicts with active work",
              details: @conflict_detector.details(blockers)
            )
          )
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
