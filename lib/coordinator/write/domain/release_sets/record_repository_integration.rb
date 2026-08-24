# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class RecordRepositoryIntegration
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new,
          digest_builder: Coordinator::Write::ReleaseSets::IntegrationDigestBuilder.new
        )
          @stream_factory = stream_factory
          @digest_builder = digest_builder
        end

        def call(state:, command:, observation:, recorded_at:)
          denial = denied(state:, command:, observation:)
          return denial if denial

          preparation = state.preparation.payload
          member = state.member(command.repository_id)
          attempt_number = state.integrations_for(command.repository_id).length + 1
          attributes = {
            release_set_id: command.release_set_id,
            release_digest: preparation.release_digest,
            repository_id: command.repository_id,
            member_position: member.position,
            attempt_id: command.attempt_id,
            attempt_number:,
            outcome: command.outcome,
            merge_observation_event: command.merge_observation_event,
            observation_digest: command.observation_digest,
            failure: command.failure,
            policy_version: command.policy_version
          }
          event = Events::RepositoryIntegrationRecordedV1.new(
            **attributes,
            change_set_id: preparation.change_set_id,
            integration_digest: @digest_builder.call(**attributes),
            evidence_status: "attributed_unverified",
            recorded_at:
          )
          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.release_set(command.release_set_id),
                  event:
                )
              ]
            )
          )
        end

        private

        def denied(state:, command:, observation:)
          return failure(:release_set_not_found, "ReleaseSet has not been prepared") unless state.preparation

          member = state.member(command.repository_id)
          return failure(:release_member_not_found, "Repository is not a member of this ReleaseSet") unless member
          return failure(:release_integration_attempt_reused, "Integration attempt ID is already recorded") if state.integrations.any? { _1.payload.attempt_id == command.attempt_id }
          return failure(:release_member_already_integrated, "Repository already has a successful integration") if state.integrated?(command.repository_id)
          if state.integrations_for(command.repository_id).length >= Types::RELEASE_SET_INTEGRATION_MAXIMUM_ATTEMPTS
            return failure(:release_integration_attempt_limit_reached, "Repository integration attempt limit was reached")
          end
          return failure(:release_integration_out_of_order, "Prior ReleaseSet members must integrate first") unless prior_members_integrated?(state, member)
          return failure(:release_integration_evidence_invalid, "Integration outcome evidence is inconsistent") unless evidence_shape_valid?(command)
          return failure(:release_integration_observation_mismatch, "Merge observation does not match the prepared member") if command.outcome == "integrated" && !observation_matches?(observation, member, command)

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

        def observation_matches?(observation, member, command)
          observation &&
            observation.merge_snapshot_id == member.merge_snapshot_id &&
            observation.authorization_event == member.authorization_event &&
            observation.authorization_decision_digest == member.authorization_decision_digest &&
            observation.snapshot_binding == member.snapshot_binding &&
            observation.repository_id == member.repository_id &&
            observation.target_branch == member.target_branch &&
            observation.object_format == member.object_format &&
            observation.target_before_commit_oid == member.target_base_commit_oid &&
            observation.target_after_commit_oid == member.merge_commit_oid &&
            observation.observation_digest == command.observation_digest
        end

        def failure(code, message, details = {})
          Failure(OutcomeError.new(code:, message:, details:))
        end
      end
    end
  end
end
