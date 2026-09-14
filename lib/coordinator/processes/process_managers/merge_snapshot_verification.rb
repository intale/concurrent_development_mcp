# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class MergeSnapshotVerification
      RULE_VERSION = "merge-snapshot-verification/v1"
      HANDLED_CODES = %i[merge_snapshot_already_verified].freeze

      def initialize(
        event_store:,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        process_step_planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:),
        verify: Coordinator::Write::Operations::ExecuteVerifyMergeSnapshot.new(event_store:)
      )
        @schema_registry = schema_registry
        @process_step_planner = process_step_planner
        @verify = verify
      end

      def call(event)
        submission = load_submission(event)
        process_step = @process_step_planner.call(
          source_event: event,
          process_name: "merge-snapshot-verification",
          step_name: "verify",
          subject_kind: "merge-snapshot",
          subject_id: submission.merge_snapshot_id,
          rule_version: RULE_VERSION,
          allocate_target_entity: false
        )
        command = Coordinator::Write::Commands::VerifyMergeSnapshot.new(
          command_id: process_step.target_command_id,
          actor: Coordinator::Write::Commands::Actor.new(
            kind: "system",
            id: "merge-snapshot-verification"
          ),
          merge_snapshot_id: submission.merge_snapshot_id,
          verification_id: submission.verification_id,
          policy_version: event.metadata.fetch("policy_version")
        )
        result = @verify.call(command, caused_by: process_step.event)
        return result.value! if result.success?
        return if HANDLED_CODES.include?(result.failure.code)

        @process_step_planner.record_dispatch_failure(process_step:, failure: result.failure)
      end

      private

      def load_submission(event)
        unless event.type == "MergeSnapshotVerificationSubmitted" &&
               event.metadata.fetch("schema_version") == 2
          raise MergeSnapshotVerificationProcessRejected, "Unsupported merge verification source"
        end

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
