# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelGuidanceAnchorResolver
      include Dry::Monads[:result]

      TARGETS = {
        "repository" => [ "DevelopmentPlanning", "Repository", "repository" ],
        "change_set" => [ "DevelopmentPlanning", "ChangeSet", "change-set" ],
        "work_item" => [ "DevelopmentExecution", "WorkItem", "work-item" ],
        "attempt" => [ "DevelopmentExecution", "Attempt", "attempt" ]
      }.freeze
      MAXIMUM_MESSAGE_ANCHORS = 103
      MAXIMUM_ATTEMPT_RELATIONSHIPS = 101

      def initialize(
        event_store:,
        entity_reference_resolver:,
        schema_registry: SourceEventSchemaRegistry.new
      )
        @event_store = event_store
        @entity_reference_resolver = entity_reference_resolver
        @schema_registry = schema_registry
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_conversation_id:,
        source_message_id:,
        anchor_kind:,
        source_anchor_id:
      )
        exact = resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          anchor_kind:,
          source_anchor_id:
        )
        return exact if exact.success? || anchor_kind != "repository"

        inferred = inferred_repository_id(
          source_upper_position:,
          source_event:,
          source_conversation_id:,
          source_message_id:
        )
        return inferred if inferred.failure?

        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          anchor_kind:,
          source_anchor_id: inferred.value!
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error,
             EventHistoryLimitExceeded => error
        Failure(invalid(source_event, error.message))
      end

      private

      def inferred_repository_id(
        source_upper_position:,
        source_event:,
        source_conversation_id:,
        source_message_id:
      )
        anchors = message_anchors(
          source_upper_position:,
          source_conversation_id:,
          source_message_id:
        )
        grouped = anchors.group_by(&:anchor_kind)
        attempt_id = sole_anchor_id(grouped, "attempt")
        work_item_id = sole_anchor_id(grouped, "work_item")
        change_set_id = sole_anchor_id(grouped, "change_set")
        unless attempt_id && work_item_id && change_set_id
          return Failure(invalid(source_event, "orphan repository anchor has no unique execution context"))
        end

        relationships = attempt_relationships(attempt_id, source_upper_position:)
        assignments = relationships.grep(Events::AttemptAssignedToWorkItemV1)
        snapshots = relationships.grep(Events::AttemptBaseSnapshotRecordedV1)
        assignment = assignments.one? ? assignments.first : nil
        repository_ids = snapshots.map(&:repository_id).uniq
        valid = assignment &&
                assignment.attempt_id == attempt_id &&
                assignment.work_item_id == work_item_id &&
                assignment.change_set_id == change_set_id &&
                snapshots.all? { _1.attempt_id == attempt_id } &&
                repository_ids.one?
        unless valid
          return Failure(invalid(source_event, "orphan repository anchor has ambiguous execution context"))
        end

        Success(repository_ids.first)
      end

      def message_anchors(source_upper_position:, source_conversation_id:, source_message_id:)
        events = @event_store.read_marked(
          StreamReference.new(
            context: "HumanGuidance",
            stream_name: "Conversation",
            stream_id: source_conversation_id
          ),
          MarkedEventReadCriteria.new(
            event_type: "GuidanceMessageAnchored",
            marker: "message:#{source_message_id}",
            maximum_count: MAXIMUM_MESSAGE_ANCHORS,
            direction: :asc
          )
        ).select { _1.global_position <= source_upper_position }
        anchors = events.map { load(_1) }
        valid = anchors.all? do |anchor|
          anchor.is_a?(Events::GuidanceMessageAnchoredV1) &&
            anchor.conversation_id == source_conversation_id &&
            anchor.message_id == source_message_id
        end
        raise ArgumentError, "guidance co-anchors are inconsistent" unless valid

        anchors
      end

      def sole_anchor_id(grouped, kind)
        ids = grouped.fetch(kind, []).map(&:anchor_id).uniq
        ids.one? ? ids.first : nil
      end

      def attempt_relationships(attempt_id, source_upper_position:)
        @event_store.read(
          StreamReference.new(
            context: "DevelopmentExecution",
            stream_name: "Attempt",
            stream_id: attempt_id
          ),
          EventReadCriteria.new(
            event_types: [ "AttemptAssignedToWorkItem", "AttemptBaseSnapshotRecorded" ],
            maximum_count: MAXIMUM_ATTEMPT_RELATIONSHIPS,
            direction: :asc
          )
        ).select { _1.global_position <= source_upper_position }.map { load(_1) }
      end

      def resolve(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        anchor_kind:,
        source_anchor_id:
      )
        target = TARGETS.fetch(anchor_kind)
        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: target.fetch(0),
            stream_name: target.fetch(1),
            stream_id: source_anchor_id
          ),
          target_stream_context: target.fetch(0),
          target_stream_name: target.fetch(1),
          identity_role: target.fetch(2)
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def invalid(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Post-remodel guidance anchor is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
