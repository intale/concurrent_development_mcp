# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module WorkIntentions
      class DeclareSet
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new, conflict_detector: ConflictDetector.new)
          @stream_factory = stream_factory
          @conflict_detector = conflict_detector
        end

        def call(
          attempt_state:,
          existing_set_state:,
          boundary:,
          command:,
          requests:,
          set_id:,
          expires_at:,
          declared_at:
        )
          denial = attempt_denied(attempt_state:, existing_set_state:, command:)
          return denial if denial

          blockers = @conflict_detector.call(
            requests:,
            observations: boundary.active_observations,
            at: declared_at
          )
          return conflict(blockers) unless blockers.empty?

          Success(
            WorkIntentionDecisionV1.write(
              build_plan(
                attempt_state:,
                boundary:,
                command:,
                requests:,
                set_id:,
                expires_at:
              )
            )
          )
        end

        private

        def attempt_denied(attempt_state:, existing_set_state:, command:)
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
          unless snapshot&.repository_id == command.repository_id && snapshot&.commit_oid == command.base_commit_oid
            return failure(:repository_base_mismatch, "Repository base does not match the Attempt", command)
          end
          return if existing_set_state.absent?

          failure(:write_set_already_reserved, "Attempt already has an initial work-intention set", command)
        end

        def build_plan(attempt_state:, boundary:, command:, requests:, set_id:, expires_at:)
          snapshot = attempt_state.base_snapshots.first
          writes = [
            EventWrite.new(
              stream: @stream_factory.work_intention_set(set_id),
              event: Events::WorkIntentionSetCreatedV1.new(
                set_id:,
                attempt_id: command.attempt_id,
                work_item_id: command.work_item_id,
                change_set_id: command.change_set_id,
                repository_id: command.repository_id
              )
            )
          ]
          requests.each do |request|
            target = request.prepared_target.target
            resource = request.resource
            intention_id = request.prepared_target.intention_id
            fencing_token = next_fencing_token(boundary.states, resource.resource_id)
            writes << EventWrite.new(
              stream: @stream_factory.resource_work_intention(intention_id),
              event: Events::ResourceWorkIntentionDeclaredV1.new(
                intention_id:,
                set_id:,
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
                fencing_token:,
                expires_at:
              )
            )
            writes << EventWrite.new(
              stream: @stream_factory.work_intention_set(set_id),
              event: Events::WorkIntentionAddedToSetV1.new(
                set_id:,
                intention_id:,
                resource_id: resource.resource_id
              )
            )
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
