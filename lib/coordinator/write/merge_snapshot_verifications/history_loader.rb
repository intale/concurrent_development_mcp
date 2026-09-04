# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class HistoryLoader
      def initialize(
        event_store:,
        snapshot_loader: MergeSnapshots::StateLoader.new(event_store:),
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        contract: Contracts::MergeSnapshotVerificationHistory.new
      )
        @event_store = event_store
        @snapshot_loader = snapshot_loader
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @contract = contract
      end

      def call(merge_snapshot_id)
        snapshot = @snapshot_loader.call(merge_snapshot_id)
        assignments = assignment_observations(merge_snapshot_id)
        submissions = assignments.map { submission_observation(_1.assignment.verification_id) }
        terminal = terminal_observation(merge_snapshot_id)
        history = Domain::MergeSnapshotVerifications::HistoryV1.new(
          snapshot:,
          assignments:,
          submissions:,
          verified: terminal
        )
        validation = @contract.call(history:, merge_snapshot_id:)
        return history if validation.success?

        raise InvalidMergeSnapshotVerificationHistory, validation.errors.to_h.inspect
      end

      private

      def assignment_observations(merge_snapshot_id)
        @event_store.read(
          @stream_factory.merge_snapshot(merge_snapshot_id),
          EventQueries::MERGE_SNAPSHOT_VERIFICATION_HISTORY
        ).map do |event|
          AssignmentObservationV1.new(assignment: load_event(event), event: event_reference(event))
        end.freeze
      end

      def submission_observation(verification_id)
        events = @event_store.read(
          @stream_factory.merge_verification(verification_id),
          EventQueries::MERGE_VERIFICATION_SUBMISSION
        )
        unless events.one?
          raise InvalidMergeSnapshotVerificationHistory,
                "Assigned merge verification #{verification_id} does not have one submission"
        end
        event = events.sole
        EvidenceObservationV1.new(
          submission: load_event(event),
          event: event_reference(event),
          policy_version: event.metadata.fetch("policy_version"),
          verification_input_digest: event.metadata.fetch("verification_input_digest")
        )
      end

      def terminal_observation(merge_snapshot_id)
        events = @event_store.read(
          @stream_factory.merge_snapshot(merge_snapshot_id),
          EventQueries::MERGE_SNAPSHOT_VERIFIED
        )
        return if events.empty?
        unless events.length == 2
          raise InvalidMergeSnapshotVerificationHistory, "Merge snapshot verification terminal facts are incomplete"
        end

        selected_event, verified_event = events
        VerifiedObservationV2.new(
          selected: load_event(selected_event),
          selected_event: event_reference(selected_event),
          verified: load_event(verified_event),
          verified_event: event_reference(verified_event),
          policy_version: verified_event.metadata.fetch("policy_version"),
          verification_digest: verified_event.metadata.fetch("verification_digest")
        )
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
    end
  end
end
