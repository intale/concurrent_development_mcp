# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteSubmitMergeSnapshotVerification < Dry::Operation
      TOOL_NAME = "merge_verification_submit"

      def initialize(
        event_store:,
        preparer: PrepareSubmitMergeSnapshotVerification.new,
        decider: Domain::MergeSnapshotVerifications::Submit.new,
        input_digest: CommandInputDigest.new,
        verification_input_digest: MergeSnapshotVerifications::VerificationInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        history_contract: Contracts::MergeSnapshotVerificationHistory.new,
        event_plan_contract: Contracts::MergeSnapshotVerificationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @decider = decider
        @input_digest = input_digest
        @verification_input_digest = verification_input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @history_contract = history_contract
        @event_plan_contract = event_plan_contract
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        steps do
          preparation = prepare_logical_values(command)
          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        MergeSnapshotVerificationPreparationV1.new(
          verification_id: @id_generator.uuid_v7,
          submitted_at: @clock.now,
          input_digest: @input_digest.merge_verification_submit(command),
          submission_event_id: @id_generator.uuid_v7,
          verified_event_id: @id_generator.uuid_v7,
          correlation_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        history = load_history(command.merge_snapshot_id)
        evidence = snapshot_evidence(history)
        verification_digest = if evidence
                                @verification_input_digest.call(
                                  policy_version: command.policy_version,
                                  snapshot: evidence,
                                  assessment: command.assessment
                                )
        else
                                preparation.input_digest
        end
        submission_event = future_submission_reference(
          command.merge_snapshot_id,
          history,
          preparation.submission_event_id
        )
        decision = @decider.call(
          history:,
          command:,
          snapshot_evidence: evidence,
          verification_id: preparation.verification_id,
          verification_input_digest: verification_digest,
          submission_event:,
          submitted_at: preparation.submitted_at
        )
        return decision if decision.failure?

        plan = decision.value!
        verify_event_plan!(
          plan,
          history:,
          command:,
          snapshot_evidence: evidence,
          preparation:,
          verification_input_digest: verification_digest,
          submission_event:
        )
        persisted = persist_plan(plan, command:, preparation:, caused_by:)
        completion = @completion_builder.merge_verification_submit(
          command:,
          submission: plan.events.fetch(0),
          input_digest: preparation.input_digest,
          persisted_events: persisted,
          completed_at: preparation.submitted_at
        )
        Success(completion)
      end

      def load_history(merge_snapshot_id)
        stream = @stream_factory.merge_snapshot(merge_snapshot_id)
        registration_event = @event_store.read(stream, EventQueries::MERGE_SNAPSHOT_REGISTRATION).first
        submission_events = @event_store.read(stream, EventQueries::MERGE_SNAPSHOT_VERIFICATION_HISTORY)
        verified_event = @event_store.read(stream, EventQueries::MERGE_SNAPSHOT_VERIFIED).first
        history = Domain::MergeSnapshotVerifications::HistoryV1.new(
          snapshot: registration_event ? load_event(registration_event) : nil,
          snapshot_event: registration_event ? event_reference(registration_event) : nil,
          submissions: submission_events.map do |event|
            MergeSnapshotVerifications::EvidenceObservationV1.new(
              submission: load_event(event),
              event: event_reference(event)
            )
          end,
          verified: verified_event ? load_event(verified_event) : nil,
          verified_event: verified_event ? event_reference(verified_event) : nil
        )
        verify_history!(history, merge_snapshot_id:)
        history
      end

      def snapshot_evidence(history)
        return unless history.snapshot

        MergeSnapshotVerifications::SnapshotEvidenceV1.new(
          snapshot: history.snapshot,
          event: history.snapshot_event
        )
      end

      def future_submission_reference(merge_snapshot_id, history, event_id)
        known = [ history.snapshot_event, *history.submissions.map(&:event), history.verified_event ].compact
        EventReference.new(
          event_id:,
          type: "MergeSnapshotVerificationSubmitted",
          stream_context: "DevelopmentIntegration",
          stream_name: "MergeSnapshot",
          stream_id: merge_snapshot_id,
          stream_revision: (known.map(&:stream_revision).max || -1) + 1
        )
      end

      def verify_history!(history, merge_snapshot_id:)
        result = @history_contract.call(history:, merge_snapshot_id:)
        return if result.success?

        raise InvalidMergeSnapshotVerificationHistory, result.errors.to_h.inspect
      end

      def verify_event_plan!(
        plan,
        history:,
        command:,
        snapshot_evidence:,
        preparation:,
        verification_input_digest:,
        submission_event:
      )
        result = @event_plan_contract.call(
          plan:,
          history:,
          command:,
          snapshot_evidence:,
          verification_id: preparation.verification_id,
          verification_input_digest:,
          submission_event:,
          submitted_at: preparation.submitted_at
        )
        return if result.success?

        raise InvalidMergeSnapshotVerificationEventPlan, result.errors.to_h.inspect
      end

      def persist_plan(plan, command:, preparation:, caused_by:)
        ids = [ preparation.submission_event_id, preparation.verified_event_id ]
        physical = plan.events.each_with_index.map do |event, index|
          @event_factory.build!(
            event:,
            event_id: ids.fetch(index),
            metadata: command_metadata(command),
            markers: event_markers(command, event),
            caused_by:,
            correlation_id: root_correlation_id(preparation, caused_by)
          )
        end
        @event_store.append(plan.writes.first.stream, physical)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def event_markers(command, event)
        common = [
          "merge-snapshot:#{command.merge_snapshot_id}",
          "repository:#{command.binding.repository_id}",
          "merge-snapshot-verification-policy:#{command.policy_version}",
          "command:#{command.command_id}"
        ]
        case event
        when Events::MergeSnapshotVerificationSubmittedV1
          common + [
            "merge-snapshot-verification:#{event.verification_id}",
            "merge-snapshot-verification-input:#{event.verification_input_digest}",
            "verification-evidence-kind:#{event.assessment.evidence_kind}",
            "verification-evidence-conclusion:#{event.assessment.conclusion}"
          ]
        when Events::MergeSnapshotVerifiedV1
          common + [
            "merge-snapshot-status:verified",
            "merge-snapshot-verification:#{event.selected_verification.verification_id}"
          ]
        end
      end

      def root_correlation_id(preparation, caused_by)
        preparation.correlation_id unless caused_by
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.policy_version
        )
      end
    end
  end
end
