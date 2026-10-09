# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateSubmissionEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::SubmitCandidate))
        required(:head_identity).value(Types.Instance(Candidates::HeadIdentityV1))
      end

      rule(:plan, :command, :head_identity) do
        command = values[:command]
        head_identity = values[:head_identity]
        candidate_stream = StreamFactory.new.candidate(command.candidate_id)
        events = expected_candidate_events(command)
        expected_events = events + [
          Events::CandidateHeadRegisteredV2.new(
            registry_id: head_identity.registry_id,
            candidate_id: command.candidate_id,
            attempt_id: command.attempt_id,
            repository_id: command.repository_id,
            object_format: command.object_format,
            head_commit_oid: command.head_commit_oid
          )
        ]
        expected_streams = Array.new(events.length, candidate_stream) + [
          StreamFactory.new.candidate_head(head_identity.registry_id)
        ]
        plan = values[:plan]

        unless plan.events == expected_events && plan.writes.map(&:stream) == expected_streams
          key(:plan).failure(
            "must preserve the exact ordered Candidate facts and natural head registration"
          )
        end
      end

      private

      def expected_candidate_events(command)
        events = [
          Events::CandidateCreatedV1.new(candidate_id: command.candidate_id),
          Events::CandidateAssignedToAttemptV1.new(
            candidate_id: command.candidate_id,
            attempt_id: command.attempt_id,
            work_item_id: command.work_item_id,
            change_set_id: command.change_set_id
          ),
          Events::CandidateAssignedToRepositoryV1.new(
            candidate_id: command.candidate_id,
            repository_id: command.repository_id
          ),
          Events::CandidateTargetBranchSelectedV1.new(
            candidate_id: command.candidate_id,
            target_branch: command.target_branch
          ),
          Events::CandidateCommitRangeDeclaredV1.new(
            candidate_id: command.candidate_id,
            object_format: command.object_format,
            base_commit_oid: command.base_commit_oid,
            head_commit_oid: command.head_commit_oid
          ),
          Events::CandidateCheckpointKindSelectedV1.new(
            candidate_id: command.candidate_id,
            checkpoint_kind: command.checkpoint_kind
          ),
          Events::CandidateWorkIntentionSetAssignedV1.new(
            candidate_id: command.candidate_id,
            intention_set_id: command.intention_set_id
          ),
          Events::CandidateChangeManifestCapturedV2.new(
            candidate_id: command.candidate_id,
            evidence_revision: 1,
            files: command.manifest.files
          )
        ]
        if command.build_context
          events << Events::CandidateBuildContextCapturedV2.new(
            candidate_id: command.candidate_id,
            evidence_revision: 1,
            inputs: command.build_context.inputs,
            environment: command.build_context.environment
          )
        end
        events << Events::CandidateSubmittedV3.new(candidate_id: command.candidate_id)
      end
    end
  end
end
