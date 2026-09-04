# frozen_string_literal: true

module Coordinator::Write
  module ChangeSetCompletions
    class WorkItemLoader
      include Dry::Monads[:result]

      def initialize(event_store:, stream_factory: StreamFactory.new, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(change_set_state)
        evidence = change_set_state.work_item_ids.map do |work_item_id|
          result = load_one(work_item_id, change_set_id: change_set_state.change_set_id)
          return result if result.failure?

          result.value!
        end
        Success(evidence.freeze)
      end

      private

      def load_one(work_item_id, change_set_id:)
        events = @event_store.read(
          @stream_factory.work_item(work_item_id),
          EventQueries::WORK_ITEM_FOR_CHANGE_SET_COMPLETION
        )
        grouped = events.to_h { [ _1.type, _1 ] }
        created = grouped["WorkItemCreated"]
        membership = grouped["WorkItemAddedToChangeSet"]
        assignment = grouped["WorkItemAssignedToRepository"]
        selected = grouped["WorkItemCandidateSelected"]
        completed = grouped["WorkItemCompleted"]
        return incomplete(work_item_id) unless created && selected && completed

        created_payload = load_event(created)
        membership_payload = membership && load_event(membership)
        assignment_payload = assignment && load_event(assignment)
        selected_payload = load_event(selected)
        completed_payload = load_event(completed)
        return invalid(work_item_id) unless coherent?(
          created_payload,
          membership_payload,
          assignment_payload,
          selected_payload,
          completed_payload,
          change_set_id:
        )

        repository_id = assignment_payload&.repository_id || created_payload.repository_id

        Success(
          WorkItemEvidenceV1.new(
            change_set_id:,
            work_item_id:,
            repository_id:,
            attempt_id: selected_payload.attempt_id,
            candidate_id: selected_payload.candidate_id,
            candidate_event: selected_payload.candidate_event,
            selected_event: event_reference(selected),
            completed_event: event_reference(completed),
            completed_at: completed.created_at.utc.iso8601(6)
          )
        )
      end

      def coherent?(created, membership, assignment, selected, completed, change_set_id:)
        return legacy_coherent?(created, selected, completed, change_set_id:) if created.is_a?(Events::WorkItemCreatedV1)

        created.is_a?(Events::WorkItemCreatedV2) &&
          membership.is_a?(Events::WorkItemAddedToChangeSetV2) &&
          assignment.is_a?(Events::WorkItemAssignedToRepositoryV1) &&
          selected.is_a?(Events::WorkItemCandidateSelectedV2) &&
          completed.is_a?(Events::WorkItemCompletedV2) &&
          membership.change_set_id == change_set_id &&
          selected.change_set_id == change_set_id &&
          [ created.work_item_id, membership.work_item_id, assignment.work_item_id,
            selected.work_item_id, completed.work_item_id ].uniq == [ created.work_item_id ]
      end

      def legacy_coherent?(created, selected, completed, change_set_id:)
        selected.is_a?(Events::WorkItemCandidateSelectedV1) &&
          completed.is_a?(Events::WorkItemCompletedV1) &&
          created.change_set_id == change_set_id &&
          selected.change_set_id == change_set_id &&
          completed.change_set_id == change_set_id &&
          created.work_item_id == selected.work_item_id &&
          selected.work_item_id == completed.work_item_id &&
          selected.attempt_id == completed.attempt_id &&
          selected.candidate_id == completed.candidate_id &&
          selected.candidate_event == completed.candidate_event
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

      def incomplete(work_item_id)
        Failure(
          OutcomeError.new(
            code: :work_item_incomplete,
            message: "Every frozen ChangeSet WorkItem must be completed",
            details: { work_item_id: }
          )
        )
      end

      def invalid(work_item_id)
        Failure(
          OutcomeError.new(
            code: :work_item_completion_invalid,
            message: "WorkItem completion history is not coherent",
            details: { work_item_id: }
          )
        )
      end
    end
  end
end
