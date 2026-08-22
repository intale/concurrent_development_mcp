# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ResourceLeases
      class Expand
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(attempt_state:, current_observations:, requested_observations:, command:, expanded_at:)
          denial = denied(
            attempt_state:,
            current_observations:,
            requested_observations:,
            command:,
            expanded_at:
          )
          return denial if denial

          Success(
            build_plan(
              attempt_state:,
              requested_observations:,
              command:,
              expanded_at:
            )
          )
        end

        private

        def denied(attempt_state:, current_observations:, requested_observations:, command:, expanded_at:)
          attempt_denial = attempt_denied(attempt_state:, command:)
          return attempt_denial if attempt_denial

          evidence_denial = evidence_denied(attempt_state:, requested_observations:, command:)
          return evidence_denial if evidence_denial

          current_denial = current_set_denied(
            attempt_state:,
            current_observations:,
            command:,
            expanded_at:
          )
          return current_denial if current_denial

          additions = additions(attempt_state:, requested_observations:)
          if additions.empty?
            return failure(:write_set_unchanged, "Every requested resource is already in the write set", command)
          end
          if attempt_state.lease_resources.length + additions.length > 32
            return failure(
              :write_set_limit_reached,
              "The expanded write set would exceed 32 resources",
              command,
              current_resource_count: attempt_state.lease_resources.length,
              requested_addition_count: additions.length
            )
          end

          busy_denied(additions:, command:, expanded_at:)
        end

        def attempt_denied(attempt_state:, command:)
          return failure(:attempt_not_found, "Attempt does not exist", command) if attempt_state.absent?
          return failure(:attempt_not_active, "Attempt is not active", command) unless attempt_state.status == "active"

          unless attempt_state.change_set_id == command.change_set_id &&
                 attempt_state.work_item_id == command.work_item_id
            return failure(:attempt_scope_mismatch, "Attempt does not belong to the requested scope", command)
          end
          unless attempt_state.agent_id == command.actor.id
            return failure(:attempt_owner_mismatch, "Attempt belongs to another agent attribution", command)
          end

          snapshot = attempt_state.base_snapshots.first
          unless snapshot.repository_id == command.repository_id && snapshot.commit_oid == command.base_commit_oid
            return failure(:repository_base_mismatch, "Repository base does not match the Attempt", command)
          end
          unless attempt_state.lease_set_id
            return failure(:write_set_not_reserved, "Attempt does not have a reserved write set", command)
          end
          unless attempt_state.lease_set_id == command.lease_set_id
            return failure(
              :lease_set_mismatch,
              "Lease-set ID does not match the Attempt's current write set",
              command,
              current_lease_set_id: attempt_state.lease_set_id,
              requested_lease_set_id: command.lease_set_id
            )
          end
          if attempt_state.lease_released_at
            return failure(
              :write_set_released,
              "The Attempt's write set has already been released",
              command,
              released_at: attempt_state.lease_released_at
            )
          end
          return if attempt_state.lease_repository_id == command.repository_id

          failure(:repository_base_mismatch, "Reserved write set belongs to another repository", command)
        end

        def evidence_denied(attempt_state:, requested_observations:, command:)
          current_by_hash = attempt_state.lease_resources.to_h { [ _1.resource_key_hash, _1 ] }
          conflict = requested_observations.find do |observation|
            resource = observation.prepared_resource.resource
            reference = current_by_hash[resource.resource_key_hash]
            reference && reference.base_blob_oid != resource.base_blob_oid
          end
          return unless conflict

          resource = conflict.prepared_resource.resource
          reference = current_by_hash.fetch(resource.resource_key_hash)
          failure(
            :resource_evidence_conflict,
            "Requested base evidence differs from the current write-set member",
            command,
            resource_key: resource.resource_key,
            resource_key_hash: resource.resource_key_hash,
            current_base_blob_oid: reference.base_blob_oid,
            requested_base_blob_oid: resource.base_blob_oid
          )
        end

        def current_set_denied(attempt_state:, current_observations:, command:, expanded_at:)
          if attempt_state.lease_expires_at <= expanded_at
            reference = attempt_state.lease_resources.first
            return failure(
              :lease_set_expired,
              "The current write set has expired",
              command,
              resource_key_hash: reference.resource_key_hash,
              lease_id: reference.lease_id,
              fencing_token: reference.fencing_token,
              expires_at: attempt_state.lease_expires_at
            )
          end

          stale = current_observations.find do |observation|
            !current_lease?(attempt_state:, observation:)
          end
          return unless stale

          failure(
            :lease_set_not_current,
            "A current write-set member is no longer owned by this lease set",
            command,
            resource_key_hash: stale.reference.resource_key_hash,
            expected_lease_id: stale.reference.lease_id,
            current_lease_id: stale.state.lease_id,
            expected_fencing_token: stale.reference.fencing_token,
            current_fencing_token: stale.state.fencing_token,
            current_lease_set_id: stale.state.lease_set_id,
            current_attempt_id: stale.state.attempt_id,
            current_expires_at: stale.state.expires_at,
            current_released_at: stale.state.released_at,
            current_expired_at: stale.state.expired_at
          )
        end

        def current_lease?(attempt_state:, observation:)
          state = observation.state
          reference = observation.reference

          state.lease_id == reference.lease_id &&
            state.lease_set_id == attempt_state.lease_set_id &&
            state.resource_key == reference.resource_key &&
            state.resource_key_hash == reference.resource_key_hash &&
            state.attempt_id == attempt_state.attempt_id &&
            state.agent_id == attempt_state.agent_id &&
            state.fencing_token == reference.fencing_token &&
            state.expires_at == attempt_state.lease_expires_at &&
            state.released_at.nil? &&
            state.expired_at.nil?
        end

        def additions(attempt_state:, requested_observations:)
          current_hashes = attempt_state.lease_resources.map(&:resource_key_hash)
          requested_observations.reject do |observation|
            current_hashes.include?(observation.prepared_resource.resource.resource_key_hash)
          end
        end

        def busy_denied(additions:, command:, expanded_at:)
          busy = additions.find { _1.state.active_at?(expanded_at) }
          return unless busy

          resource = busy.prepared_resource.resource
          state = busy.state
          Failure(
            OutcomeError.new(
              code: :lease_busy,
              message: "A requested resource already has an active exclusive lease",
              details: {
                resource_key: resource.resource_key,
                resource_key_hash: resource.resource_key_hash,
                lease_id: state.lease_id,
                owner_attempt_id: state.attempt_id,
                owner_agent_id: state.agent_id,
                fencing_token: state.fencing_token,
                expires_at: state.expires_at
              }
            )
          )
        end

        def build_plan(attempt_state:, requested_observations:, command:, expanded_at:)
          additions = additions(attempt_state:, requested_observations:)
          snapshot = attempt_state.base_snapshots.first
          acquisitions = additions.map do |observation|
            build_acquisition(
              observation:,
              attempt_state:,
              command:,
              snapshot:,
              expanded_at:
            )
          end
          references = acquisitions.map { lease_reference(_1) }

          EventPlan.new(
            writes: acquisitions.map do |event|
              EventWrite.new(
                stream: @stream_factory.resource_lease(event.resource_key_hash),
                event:
              )
            end + [
              EventWrite.new(
                stream: @stream_factory.attempt(command.attempt_id),
                event: Events::WriteSetExpandedV1.new(
                  lease_set_id: command.lease_set_id,
                  change_set_id: command.change_set_id,
                  work_item_id: command.work_item_id,
                  attempt_id: command.attempt_id,
                  repository_id: command.repository_id,
                  policy_version: attempt_state.lease_policy_version,
                  added_resources: references,
                  resource_count: attempt_state.lease_resources.length + references.length,
                  expanded_at:,
                  expires_at: attempt_state.lease_expires_at
                )
              )
            ]
          )
        end

        def build_acquisition(observation:, attempt_state:, command:, snapshot:, expanded_at:)
          prepared = observation.prepared_resource
          resource = prepared.resource
          Events::ResourceLeaseAcquiredV1.new(
            lease_id: prepared.lease_id,
            lease_set_id: command.lease_set_id,
            resource_key: resource.resource_key,
            resource_key_hash: resource.resource_key_hash,
            resource_kind: resource.kind,
            resource_path: resource.path,
            policy_version: resource.policy_version,
            mode: "exclusive",
            change_set_id: command.change_set_id,
            work_item_id: command.work_item_id,
            attempt_id: command.attempt_id,
            agent_id: command.actor.id,
            repository_id: command.repository_id,
            object_format: snapshot.object_format,
            base_commit_oid: command.base_commit_oid,
            base_blob_oid: resource.base_blob_oid,
            fencing_token: observation.state.next_fencing_token,
            acquired_at: expanded_at,
            expires_at: attempt_state.lease_expires_at
          )
        end

        def lease_reference(event)
          LeaseReferenceV1.new(
            lease_id: event.lease_id,
            resource_key: event.resource_key,
            resource_key_hash: event.resource_key_hash,
            resource_kind: event.resource_kind,
            resource_path: event.resource_path,
            base_blob_oid: event.base_blob_oid,
            fencing_token: event.fencing_token
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
