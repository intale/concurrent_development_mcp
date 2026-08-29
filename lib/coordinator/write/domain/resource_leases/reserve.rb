# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ResourceLeases
      class Reserve
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(
          attempt_state:,
          lease_states:,
          command:,
          resources:,
          lease_set_id:,
          lease_ids:,
          acquired_at:,
          expires_at:
        )
          denial = denied(attempt_state:, lease_states:, command:, resources:, acquired_at:)
          return denial if denial

          Success(
            build_plan(
              attempt_state:,
              lease_states:,
              command:,
              resources:,
              lease_set_id:,
              lease_ids:,
              acquired_at:,
              expires_at:
            )
          )
        end

        private

        def denied(attempt_state:, lease_states:, command:, resources:, acquired_at:)
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
          if attempt_state.lease_set_id
            return failure(:write_set_already_reserved, "Attempt already has an initial write set", command)
          end

          busy = resources.lazy.filter_map do |resource|
            state = lease_states.find do |candidate|
              candidate.active_at?(acquired_at) && resources_overlap?(resource, candidate)
            end
            [ resource, state ] if state
          end.first
          return unless busy

          resource, busy_state = busy
          Failure(
            OutcomeError.new(
              code: :lease_busy,
              message: "A requested resource already has an active exclusive lease",
              details: {
                resource_id: resource.resource_id,
                lease_id: busy_state.lease_id,
                owner_attempt_id: busy_state.attempt_id,
                owner_agent_id: busy_state.agent_id,
                fencing_token: busy_state.fencing_token,
                expires_at: busy_state.expires_at
              }
            )
          )
        end

        def resources_overlap?(resource, state)
          return true if resource.path == state.resource_path

          (resource.kind == "directory" && state.resource_path.start_with?("#{resource.path}/")) ||
            (state.resource_kind == "directory" && resource.path.start_with?("#{state.resource_path}/"))
        end

        def build_plan(
          attempt_state:,
          lease_states:,
          command:,
          resources:,
          lease_set_id:,
          lease_ids:,
          acquired_at:,
          expires_at:
        )
          snapshot = attempt_state.base_snapshots.first
          acquisitions = resources.each_with_index.map do |resource, index|
            build_acquisition(
              resource:,
              state: lease_states.fetch(index),
              command:,
              snapshot:,
              lease_set_id:,
              lease_id: lease_ids.fetch(index),
              acquired_at:,
              expires_at:
            )
          end
          references = acquisitions.map { lease_reference(_1) }

          EventPlan.new(
            writes: acquisitions.map do |event|
              EventWrite.new(
                stream: @stream_factory.resource_lease(event.resource_id),
                event:
              )
            end + [
              EventWrite.new(
                stream: @stream_factory.attempt(command.attempt_id),
                event: Events::WriteSetReservedV2.new(
                  lease_set_id:,
                  change_set_id: command.change_set_id,
                  work_item_id: command.work_item_id,
                  attempt_id: command.attempt_id,
                  repository_id: command.repository_id,
                  policy_version: LeaseResourceV2::POLICY_VERSION,
                  resources: references,
                  reserved_at: acquired_at,
                  expires_at:
                )
              )
            ]
          )
        end

        def build_acquisition(resource:, state:, command:, snapshot:, lease_set_id:, lease_id:, acquired_at:, expires_at:)
          Events::ResourceLeaseAcquiredV2.new(
            lease_id:,
            lease_set_id:,
            resource_id: resource.resource_id,
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
            fencing_token: state.next_fencing_token,
            acquired_at:,
            expires_at:
          )
        end

        def lease_reference(event)
          LeaseReferenceV2.new(
            lease_id: event.lease_id,
            resource_id: event.resource_id,
            resource_kind: event.resource_kind,
            resource_path: event.resource_path,
            base_blob_oid: event.base_blob_oid,
            fencing_token: event.fencing_token
          )
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
