# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ResourceLeases
      class Renew
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(attempt_state:, current_observations:, command:, renewed_at:, expires_at:)
          denial = denied(
            attempt_state:,
            current_observations:,
            command:,
            renewed_at:,
            expires_at:
          )
          return denial if denial

          Success(
            build_plan(
              attempt_state:,
              current_observations:,
              command:,
              renewed_at:,
              expires_at:
            )
          )
        end

        private

        def denied(attempt_state:, current_observations:, command:, renewed_at:, expires_at:)
          attempt_denial = attempt_denied(attempt_state:, command:)
          return attempt_denial if attempt_denial

          snapshot_denial = snapshot_denied(attempt_state:, command:)
          return snapshot_denial if snapshot_denial

          current_denial = current_set_denied(
            attempt_state:,
            current_observations:,
            command:,
            renewed_at:
          )
          return current_denial if current_denial

          return unless expires_at <= attempt_state.lease_expires_at

          failure(
            :lease_deadline_not_extended,
            "The requested duration does not extend the current lease-set deadline",
            command,
            current_expires_at: attempt_state.lease_expires_at,
            requested_expires_at: expires_at
          )
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

          nil
        end

        def snapshot_denied(attempt_state:, command:)
          current_hashes = attempt_state.lease_resources.map(&:resource_key_hash)
          requested_hashes = command.leases.map(&:resource_key_hash)
          unless requested_hashes == current_hashes
            return failure(
              :lease_set_snapshot_mismatch,
              "Submitted lease members do not equal the Attempt's current write set",
              command,
              current_resource_key_hashes: current_hashes,
              requested_resource_key_hashes: requested_hashes
            )
          end

          current_by_hash = attempt_state.lease_resources.to_h { [ _1.resource_key_hash, _1 ] }
          mismatch = command.leases.find do |submitted|
            current = current_by_hash.fetch(submitted.resource_key_hash)
            submitted.lease_id != current.lease_id || submitted.fencing_token != current.fencing_token
          end
          return unless mismatch

          current = current_by_hash.fetch(mismatch.resource_key_hash)
          failure(
            :lease_reference_mismatch,
            "Submitted lease identity or fencing token is stale",
            command,
            resource_key_hash: mismatch.resource_key_hash,
            current_lease_id: current.lease_id,
            requested_lease_id: mismatch.lease_id,
            current_fencing_token: current.fencing_token,
            requested_fencing_token: mismatch.fencing_token
          )
        end

        def current_set_denied(attempt_state:, current_observations:, command:, renewed_at:)
          stale = current_observations.find do |observation|
            !current_lease?(attempt_state:, observation:)
          end
          if stale
            return failure(
              :lease_set_not_current,
              "A write-set member is no longer owned by this lease set",
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

          return unless attempt_state.lease_expires_at <= renewed_at

          reference = attempt_state.lease_resources.first
          failure(
            :lease_set_expired,
            "The current write set has expired and cannot be renewed",
            command,
            resource_key_hash: reference.resource_key_hash,
            lease_id: reference.lease_id,
            fencing_token: reference.fencing_token,
            expires_at: attempt_state.lease_expires_at
          )
        end

        def current_lease?(attempt_state:, observation:)
          state = observation.state
          reference = observation.reference
          snapshot = attempt_state.base_snapshots.first

          state.lease_id == reference.lease_id &&
            state.lease_set_id == attempt_state.lease_set_id &&
            state.resource_key == reference.resource_key &&
            state.resource_key_hash == reference.resource_key_hash &&
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

        def build_plan(attempt_state:, current_observations:, command:, renewed_at:, expires_at:)
          renewals = current_observations.map do |observation|
            build_renewal(
              attempt_state:,
              reference: observation.reference,
              command:,
              renewed_at:,
              expires_at:
            )
          end

          EventPlan.new(
            writes: renewals.map do |event|
              EventWrite.new(
                stream: @stream_factory.resource_lease(event.resource_key_hash),
                event:
              )
            end + [
              EventWrite.new(
                stream: @stream_factory.attempt(command.attempt_id),
                event: Events::WriteSetRenewedV1.new(
                  lease_set_id: command.lease_set_id,
                  change_set_id: command.change_set_id,
                  work_item_id: command.work_item_id,
                  attempt_id: command.attempt_id,
                  repository_id: attempt_state.lease_repository_id,
                  policy_version: attempt_state.lease_policy_version,
                  resources: attempt_state.lease_resources,
                  resource_count: attempt_state.lease_resources.length,
                  renewed_at:,
                  previous_expires_at: attempt_state.lease_expires_at,
                  expires_at:
                )
              )
            ]
          )
        end

        def build_renewal(attempt_state:, reference:, command:, renewed_at:, expires_at:)
          snapshot = attempt_state.base_snapshots.first
          Events::ResourceLeaseRenewedV1.new(
            lease_id: reference.lease_id,
            lease_set_id: command.lease_set_id,
            resource_key: reference.resource_key,
            resource_key_hash: reference.resource_key_hash,
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
            renewed_at:,
            previous_expires_at: attempt_state.lease_expires_at,
            expires_at:
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
