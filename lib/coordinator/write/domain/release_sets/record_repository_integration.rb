# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class RecordRepositoryIntegration
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, observation:)
          denial = denied(state:, command:, observation:)
          return denial if denial

          preparation = state.preparation.payload
          member = state.member(command.repository_id)
          attempt_number = state.integrations_for(command.repository_id).length + 1
          stream = @stream_factory.release_set(command.release_set_id)
          writes = [
            EventWrite.new(
              stream:,
              event: Events::RepositoryIntegrationRecordedV2.new(
                release_set_id: command.release_set_id,
                change_set_id: preparation.change_set_id,
                repository_id: command.repository_id,
                attempt_id: command.attempt_id,
                attempt_number:,
                member_position: member.position,
                outcome: command.outcome,
                failure: command.failure
              )
            )
          ]
          if command.outcome == "integrated"
            writes << EventWrite.new(
              stream:,
              event: Events::RepositoryIntegrationMergeLinkedV1.new(
                release_set_id: command.release_set_id,
                repository_id: command.repository_id,
                merge_observation: command.merge_observation_event
              )
            )
          end
          Success(EventPlan.new(writes:))
        end

        private

        def denied(state:, command:, observation:)
          return failure(:release_set_not_found, "ReleaseSet has not been prepared") unless state.preparation
          return failure(:release_set_already_completed, "ReleaseSet is already completed") if state.completed?
          return failure(:release_set_compensation_requested, "ReleaseSet compensation has been requested") if state.compensation_requested?
          return failure(:release_set_already_activated, "ReleaseSet is already activated") if state.activated?

          member = state.member(command.repository_id)
          return failure(:release_member_not_found, "Repository is not a member of this ReleaseSet") unless member
          return failure(:release_integration_attempt_reused, "Integration attempt ID is already recorded") if state.integrations.any? { _1.payload.attempt_id == command.attempt_id }
          return failure(:release_member_already_integrated, "Repository already has a successful integration") if state.integrated?(command.repository_id)
          if state.integrations_for(command.repository_id).length >= Types::RELEASE_SET_INTEGRATION_MAXIMUM_ATTEMPTS
            return failure(:release_integration_attempt_limit_reached, "Repository integration attempt limit was reached")
          end
          return failure(:release_integration_out_of_order, "Prior ReleaseSet members must integrate first") unless prior_members_integrated?(state, member)
          return failure(:release_integration_evidence_invalid, "Integration outcome evidence is inconsistent") unless evidence_shape_valid?(command)
          if command.outcome == "integrated" && !observation_matches?(observation, member, command)
            return failure(:release_integration_observation_mismatch, "Merge observation does not match the prepared member")
          end

          nil
        end

        def prior_members_integrated?(state, member)
          state.preparation.payload.ordered_members
            .take(member.position - 1)
            .all? { state.integrated?(_1.repository_id) }
        end

        def evidence_shape_valid?(command)
          if command.outcome == "integrated"
            command.merge_observation_event && command.observation_digest && command.failure.nil?
          else
            command.merge_observation_event.nil? && command.observation_digest.nil? && command.failure
          end
        end

        def observation_matches?(evidence, member, command)
          return false unless evidence

          observation = evidence.observation
          snapshot = evidence.snapshot
          evidence.event == command.merge_observation_event &&
            evidence.observation_digest == command.observation_digest &&
            snapshot.ordered_candidates.one? &&
            snapshot.ordered_candidates.sole.candidate_id == member.candidate_id &&
            snapshot.repository_id == member.repository_id &&
            observation.merge_snapshot_id == snapshot.merge_snapshot_id &&
            observation.repository_id == snapshot.repository_id &&
            observation.target_branch == snapshot.target_branch &&
            observation.object_format == snapshot.object_format &&
            observation.target_before_commit_oid == snapshot.target_base_commit_oid &&
            observation.target_after_commit_oid == snapshot.merge_commit_oid
        end

        def failure(code, message, details = {})
          Failure(OutcomeError.new(code:, message:, details:))
        end
      end
    end
  end
end
