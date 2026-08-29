# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Attempts
      class Abandon
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(attempt_state:, work_item_state:, current_observations:, command:, abandoned_at:)
          denial = denied(
            attempt_state:,
            work_item_state:,
            command:
          )
          return denial if denial

          Success(
            build_plan(
              attempt_state:,
              current_observations:,
              command:,
              abandoned_at:
            )
          )
        end

        private

        def denied(attempt_state:, work_item_state:, command:)
          attempt_denial = attempt_denied(attempt_state:, command:)
          return attempt_denial if attempt_denial

          work_item_denied(work_item_state:, command:)
        end

        def attempt_denied(attempt_state:, command:)
          return failure(:attempt_not_found, "Attempt does not exist", command) if attempt_state.absent?
          unless attempt_state.status == "active"
            return failure(:attempt_not_active, "Attempt is not active and cannot be abandoned", command)
          end
          if attempt_state.selected_candidate_checkpoint_kind == "final"
            return failure(
              :attempt_not_active,
              "Attempt has a final Candidate and must be completed instead of abandoned",
              command
            )
          end
          unless attempt_state.attempt_id == command.attempt_id &&
                 attempt_state.change_set_id == command.change_set_id &&
                 attempt_state.work_item_id == command.work_item_id
            return failure(:attempt_scope_mismatch, "Attempt does not belong to the requested scope", command)
          end
          return if attempt_state.agent_id == command.actor.id

          failure(:attempt_owner_mismatch, "Attempt belongs to another agent attribution", command)
        end

        def work_item_denied(work_item_state:, command:)
          unless work_item_state.status == "active" &&
                 work_item_state.change_set_id == command.change_set_id &&
                 work_item_state.work_item_id == command.work_item_id &&
                 work_item_state.active_attempt_id == command.attempt_id
            return failure(
              :work_item_unavailable,
              "WorkItem is not active under the requested Attempt",
              command
            )
          end
          return if work_item_state.active_agent_id == command.actor.id

          failure(:attempt_owner_mismatch, "WorkItem belongs to another agent attribution", command)
        end

        def build_plan(attempt_state:, current_observations:, command:, abandoned_at:)
          releasable, untouched = current_observations.partition do |observation|
            current_lease?(
              attempt_state:,
              observation:,
              abandoned_at:
            )
          end
          release_events = releasable.map do |observation|
            build_release(
              attempt_state:,
              observation:,
              command:,
              abandoned_at:
            )
          end
          released_references = releasable.map(&:reference).sort_by { lease_identity(_1).b }
          untouched_identities = untouched.map { lease_identity(_1.reference) }.sort

          EventPlan.new(
            writes: release_events.map do |event|
              EventWrite.new(
                stream: @stream_factory.resource_lease(lease_identity(event)),
                event:
              )
            end + [
              EventWrite.new(
                stream: @stream_factory.attempt(command.attempt_id),
                event: build_abandonment(
                  attempt_state:,
                  command:,
                  released_references:,
                  untouched_identities:,
                  abandoned_at:
                )
              ),
              EventWrite.new(
                stream: @stream_factory.work_item(command.work_item_id),
                event: Events::WorkItemRequeuedV1.new(
                  change_set_id: command.change_set_id,
                  work_item_id: command.work_item_id,
                  attempt_id: command.attempt_id,
                  agent_id: command.actor.id,
                  reason: command.reason,
                  requeued_at: abandoned_at
                )
              )
            ]
          )
        end

        def current_lease?(attempt_state:, observation:, abandoned_at:)
          state = observation.state
          reference = observation.reference
          snapshot = attempt_state.base_snapshots.first
          return false unless snapshot

          state.active_at?(abandoned_at) &&
            state.lease_id == reference.lease_id &&
            state.lease_set_id == attempt_state.lease_set_id &&
            state.identity == lease_identity(reference) &&
            state.resource_kind == reference.resource_kind &&
            state.resource_path == reference.resource_path &&
            state.base_blob_oid == reference.base_blob_oid &&
            state.policy_version == attempt_state.lease_policy_version &&
            state.mode == "exclusive" &&
            state.change_set_id == attempt_state.change_set_id &&
            state.work_item_id == attempt_state.work_item_id &&
            state.attempt_id == attempt_state.attempt_id &&
            state.agent_id == attempt_state.agent_id &&
            state.repository_id == attempt_state.lease_repository_id &&
            state.object_format == snapshot.object_format &&
            state.base_commit_oid == snapshot.commit_oid &&
            state.fencing_token == reference.fencing_token &&
            state.expires_at == attempt_state.lease_expires_at &&
            state.released_at.nil? &&
            state.expired_at.nil?
        end

        def build_release(attempt_state:, observation:, command:, abandoned_at:)
          reference = observation.reference
          state = observation.state
          snapshot = attempt_state.base_snapshots.first

          attributes = {
            lease_id: reference.lease_id,
            lease_set_id: attempt_state.lease_set_id,
            resource_kind: reference.resource_kind,
            resource_path: reference.resource_path,
            policy_version: attempt_state.lease_policy_version,
            mode: "exclusive",
            change_set_id: command.change_set_id,
            work_item_id: command.work_item_id,
            attempt_id: command.attempt_id,
            agent_id: command.actor.id,
            repository_id: attempt_state.lease_repository_id,
            object_format: snapshot.object_format,
            base_commit_oid: snapshot.commit_oid,
            base_blob_oid: reference.base_blob_oid,
            fencing_token: reference.fencing_token,
            acquired_at: state.acquired_at,
            previous_expires_at: state.expires_at,
            released_at: abandoned_at
          }
          if reference.respond_to?(:resource_id)
            return Events::ResourceLeaseReleasedV2.new(**attributes, resource_id: reference.resource_id)
          end

          Events::ResourceLeaseReleasedV1.new(
            **attributes,
            resource_key: reference.resource_key,
            resource_key_hash: reference.resource_key_hash
          )
        end

        def build_abandonment(attempt_state:, command:, released_references:, untouched_identities:, abandoned_at:)
          attributes = {
            change_set_id: command.change_set_id,
            work_item_id: command.work_item_id,
            attempt_id: command.attempt_id,
            agent_id: command.actor.id,
            reason: command.reason,
            lease_set_id: attempt_state.lease_set_id,
            released_leases: released_references,
            abandoned_at:
          }
          if attempt_state.lease_policy_version == LeaseResourceV2::POLICY_VERSION
            return Events::AttemptAbandonedV2.new(
              **attributes,
              untouched_resource_ids: untouched_identities
            )
          end

          Events::AttemptAbandonedV1.new(
            **attributes,
            untouched_resource_key_hashes: untouched_identities
          )
        end

        def lease_identity(value)
          return value.resource_id if value.respond_to?(:resource_id)

          value.resource_key_hash
        end

        def failure(code, message, command)
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: {
                change_set_id: command.change_set_id,
                work_item_id: command.work_item_id,
                attempt_id: command.attempt_id
              }
            )
          )
        end
      end
    end
  end
end
