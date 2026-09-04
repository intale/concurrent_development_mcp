# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class MergeAuthorizationEvaluation < Dry::Validation::Contract
      params do
        required(:evaluation).value(Types.Instance(MergeAuthorizations::EvaluationV1))
        required(:command).value(Types.Instance(Commands::RequestMergeAuthorization))
      end

      rule(:evaluation, :command) do
        evaluation = values[:evaluation]
        command = values[:command]
        unless evaluation.merge_snapshot_id == command.merge_snapshot_id &&
               evaluation.target_base_observation == command.target_base_observation
          key(:evaluation).failure("must preserve the requested snapshot and target-base observation")
          next
        end

        if evaluation.snapshot
          key(:evaluation).failure("must contain coherent snapshot evidence") unless coherent_snapshot?(evaluation.snapshot, command)
        elsif evaluation.reasons.none? { _1.code == "merge_snapshot_not_found" }
          key(:evaluation).failure("must explain absent snapshot evidence")
        end

        if evaluation.granted?
          key(:evaluation).failure("must contain verified snapshot evidence") unless evaluation.snapshot
          key(:evaluation).failure("must contain current policy evidence") unless evaluation.current_policy
          unless expected_policy_matches?(command.expected_impact_policy, evaluation.current_policy)
            key(:evaluation).failure("must grant only against the caller's exact current policy context")
          end
          unless evaluation.obligations.all? { %w[satisfied waived].include?(_1.status) }
            key(:evaluation).failure("must grant only when every required obligation permits integration")
          end
          unless exact_work_item_progress?(evaluation)
            key(:evaluation).failure("must grant only with exact selected, completed, dependency-satisfied WorkItem evidence")
          end
        elsif evaluation.reasons.empty?
          key(:evaluation).failure("must explain a denied authorization")
        end

        candidate_ids = evaluation.candidates.map(&:candidate_id)
        key(:evaluation).failure("must not repeat Candidate evidence") unless candidate_ids.uniq.length == candidate_ids.length
        obligation_ids = evaluation.obligations.map(&:obligation_id).compact
        key(:evaluation).failure("must not repeat obligation checks") unless obligation_ids.uniq.length == obligation_ids.length
        progress_ids = evaluation.work_item_progress.map { [ _1.work_item_id, _1.candidate_id ] }
        key(:evaluation).failure("must not repeat WorkItem progress evidence") unless progress_ids.uniq.length == progress_ids.length
        unless evaluation.work_item_progress.all? { unique_dependencies?(_1) }
          key(:evaluation).failure("must not repeat dependency progress evidence")
        end
      end

      private

      def coherent_snapshot?(evidence, command)
        registration = evidence.registration
        verification = evidence.verification
        binding = command.snapshot_binding
        registration_valid = registration.merge_snapshot_id == command.merge_snapshot_id &&
          evidence.registration_event == binding.registration_event &&
          registration.snapshot_digest == binding.snapshot_digest
        return registration_valid unless verification

        registration_valid &&
          evidence.verification_event == binding.verification_event &&
          verification.verification_digest == binding.verification_digest &&
          verification.verified.merge_snapshot_id == registration.merge_snapshot_id &&
          verification.selected.merge_snapshot_id == registration.merge_snapshot_id
      end

      def expected_policy_matches?(expected, current)
        if current.status == "absent"
          expected.nil? && current.partition_event.nil? && current.head.nil? && current.definition_digest.nil?
        else
          expected && expected.partition_event == current.partition_event &&
            expected.head == current.head && expected.definition_digest == current.definition_digest
        end
      end

      def exact_work_item_progress?(evaluation)
        expected = evaluation.snapshot.registration.ordered_candidates.map do |candidate|
          [
            candidate.change_set_id,
            candidate.work_item_id,
            candidate.repository_id,
            candidate.attempt_id,
            candidate.candidate_id,
            candidate.candidate_event
          ]
        end
        observed = evaluation.work_item_progress.map do |progress|
          [
            progress.change_set_id,
            progress.work_item_id,
            progress.repository_id,
            progress.attempt_id,
            progress.candidate_id,
            progress.candidate_event
          ]
        end
        expected == observed
      end

      def unique_dependencies?(progress)
        ids = progress.incoming_dependencies.map(&:dependency_id)
        ids.uniq.length == ids.length
      end
    end
  end
end
