# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateSubmissionEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::SubmitCandidate))
        required(:state).value(Types.Instance(Domain::Candidates::SubmissionState))
        required(:head_identity).value(Types.Instance(Candidates::HeadIdentityV1))
        required(:candidate_event).value(Types.Instance(EventReference))
        required(:submitted_at).filled(:string)
      end

      rule(:plan, :command, :state, :head_identity, :candidate_event, :submitted_at) do
        command = values[:command]
        state = values[:state]
        head_identity = values[:head_identity]
        candidate_event = values[:candidate_event]
        submitted_at = values[:submitted_at]
        expected_events = expected_events(
          command:,
          state:,
          head_identity:,
          candidate_event:,
          submitted_at:
        )
        expected_streams = expected_streams(command:, head_identity:)
        plan = values[:plan]

        unless plan.events == expected_events && plan.writes.map(&:stream) == expected_streams
          key(:plan).failure(
            "must preserve the exact ordered Candidate, evidence, head-registry, and Attempt facts"
          )
        end
      end

      private

      def expected_events(command:, state:, head_identity:, candidate_event:, submitted_at:)
        events = [ candidate_submitted(command:, state:, submitted_at:) ]
        events << manifest_captured(command:, submitted_at:)
        events << build_context_captured(command:, submitted_at:) if command.build_context
        events << head_registered(command:, head_identity:, candidate_event:, submitted_at:)
        events << attached(command:, candidate_event:, submitted_at:)
        events
      end

      def candidate_submitted(command:, state:, submitted_at:)
        Events::CandidateSubmittedV1.new(
          candidate_id: command.candidate_id,
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          agent_id: command.actor.id,
          repository_id: command.repository_id,
          target_branch: command.target_branch,
          object_format: command.object_format,
          base_commit_oid: command.base_commit_oid,
          head_commit_oid: command.head_commit_oid,
          checkpoint_kind: command.checkpoint_kind,
          lease_set_id: command.lease_set_id,
          lease_policy_version: state.attempt.lease_policy_version,
          lease_references: state.attempt.lease_resources,
          manifest_digest: command.manifest.digest,
          build_context_digest: command.build_context&.digest,
          evidence_status: "attributed_unverified",
          submitted_at:
        )
      end

      def manifest_captured(command:, submitted_at:)
        manifest = command.manifest
        Events::CandidateChangeManifestCapturedV1.new(
          candidate_id: command.candidate_id,
          repository_id: command.repository_id,
          target_branch: command.target_branch,
          object_format: command.object_format,
          base_commit_oid: command.base_commit_oid,
          head_commit_oid: command.head_commit_oid,
          evidence_revision: 1,
          policy_version: manifest.policy_version,
          manifest_digest: manifest.digest,
          files: manifest.files,
          collector: manifest.collector,
          captured_at: submitted_at
        )
      end

      def build_context_captured(command:, submitted_at:)
        context = command.build_context
        Events::CandidateBuildContextCapturedV1.new(
          candidate_id: command.candidate_id,
          repository_id: command.repository_id,
          object_format: command.object_format,
          head_commit_oid: command.head_commit_oid,
          evidence_revision: 1,
          policy_version: context.policy_version,
          build_context_digest: context.digest,
          inputs: context.inputs,
          environment: context.environment,
          dependency_graph_digest: context.dependency_graph_digest,
          test_environment_digest: context.test_environment_digest,
          collector: context.collector,
          captured_at: submitted_at
        )
      end

      def head_registered(command:, head_identity:, candidate_event:, submitted_at:)
        Events::CandidateHeadRegisteredV1.new(
          registry_id: head_identity.registry_id,
          candidate_id: command.candidate_id,
          attempt_id: command.attempt_id,
          repository_id: command.repository_id,
          object_format: command.object_format,
          head_commit_oid: command.head_commit_oid,
          candidate_event:,
          registered_at: submitted_at
        )
      end

      def attached(command:, candidate_event:, submitted_at:)
        Events::CandidateAttachedToAttemptV1.new(
          candidate_id: command.candidate_id,
          candidate_event:,
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: command.repository_id,
          target_branch: command.target_branch,
          object_format: command.object_format,
          base_commit_oid: command.base_commit_oid,
          head_commit_oid: command.head_commit_oid,
          checkpoint_kind: command.checkpoint_kind,
          manifest_digest: command.manifest.digest,
          build_context_digest: command.build_context&.digest,
          attached_at: submitted_at
        )
      end

      def expected_streams(command:, head_identity:)
        streams = StreamFactory.new
        candidate_stream = streams.candidate(command.candidate_id)
        result = [ candidate_stream, candidate_stream ]
        result << candidate_stream if command.build_context
        result << streams.candidate_head(head_identity.registry_id)
        result << streams.attempt(command.attempt_id)
        result
      end
    end
  end
end
