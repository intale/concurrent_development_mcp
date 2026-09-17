# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelWorkItemTransformer
      include Dry::Monads[:result]

      SOURCE_REFERENCE_STEPS = {
        "WorkItemCandidateSelected" => "select-work-item-candidate",
        "WorkItemCompleted" => "complete-work-item"
      }.freeze

      def initialize(
        stream_identity_allocator:,
        entity_reference_resolver:,
        target_event_reference_resolver:
      )
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @target_event_reference_resolver = target_event_reference_resolver
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        allocation = resolve_work_item(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_payload
        )
        return allocation if allocation.failure?

        transform(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_payload,
          target_stream: allocation.value!.target_stream
        )
      end

      private

      def resolve_work_item(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        if source_event.stream.context == "DevelopmentExecution" &&
            source_event.stream.stream_name == "WorkItem"
          return @stream_identity_allocator.call(
            migration_id:,
            source_config_name:,
            source_event:,
            target_stream_context: "DevelopmentExecution",
            target_stream_name: "WorkItem",
            identity_role: "work-item"
          )
        end

        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: "DevelopmentExecution",
            stream_name: "WorkItem",
            stream_id: source.consumer_work_item_id
          ),
          target_stream_context: "DevelopmentExecution",
          target_stream_name: "WorkItem",
          identity_role: "work-item"
        )
      end

      def transform(migration_id:, source_config_name:, source_upper_position:, source_event:, source:, target_stream:)
        case source
        when Events::WorkItemMadeReadyV2
          with_change_set(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_id: source.change_set_id
          ) do |change_set_id|
            build(
              target_stream:,
              event: Events::WorkItemMadeReadyV2.new(
                work_item_id: target_stream.stream_id,
                change_set_id:,
                readiness_decision_id: source.readiness_decision_id,
                reason: source.reason
              ),
              markers: markers(target_stream.stream_id, change_set_id:) +
                [ "readiness-decision:#{source.readiness_decision_id}" ],
              step_name: "make-work-item-ready",
              source_event:
            )
          end
        when Events::WorkItemAcquiredV2, Events::WorkItemRequeuedV2
          transform_attempt_lifecycle(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::WorkItemCandidateSelectedV2
          transform_candidate_selection(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::WorkItemDependencySatisfiedV2
          transform_dependency_satisfaction(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            target_stream:
          )
        when Events::WorkItemCompletedV2
          Success([
            build(
              target_stream:,
              event: Events::WorkItemCompletedV2.new(work_item_id: target_stream.stream_id),
              markers: markers(target_stream.stream_id),
              step_name: "complete-work-item",
              source_event:
            )
          ])
        end
      end

      def transform_attempt_lifecycle(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        change_set = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentPlanning",
          source_name: "ChangeSet",
          source_id: source.change_set_id,
          target_context: "DevelopmentPlanning",
          target_name: "ChangeSet",
          identity_role: "change-set"
        )
        return change_set if change_set.failure?

        attempt = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentExecution",
          source_name: "Attempt",
          source_id: source.attempt_id,
          target_context: "DevelopmentExecution",
          target_name: "Attempt",
          identity_role: "attempt"
        )
        return attempt if attempt.failure?

        work_item_id = target_stream.stream_id
        change_set_id = change_set.value!.target_stream.stream_id
        attempt_id = attempt.value!.target_stream.stream_id
        event, step_name = if source.is_a?(Events::WorkItemAcquiredV2)
          [
            Events::WorkItemAcquiredV2.new(
              work_item_id:,
              change_set_id:,
              attempt_id:,
              agent_id: source.agent_id
            ),
            "acquire-work-item"
          ]
        else
          [
            Events::WorkItemRequeuedV2.new(
              work_item_id:,
              change_set_id:,
              attempt_id:,
              agent_id: source.agent_id,
              reason: source.reason
            ),
            "requeue-work-item"
          ]
        end
        Success([
          build(
            target_stream:,
            event:,
            markers: markers(work_item_id, change_set_id:, attempt_id:),
            step_name:,
            source_event:
          )
        ])
      end

      def transform_candidate_selection(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        relationships = resolve_change_set_and_attempt(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          change_set_id: source.change_set_id,
          attempt_id: source.attempt_id
        )
        return relationships if relationships.failure?

        candidate = @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.candidate_event,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "Candidate",
          identity_role: "candidate",
          target_event_type: "CandidateSubmitted",
          target_step_name: "submit-candidate"
        )
        return candidate if candidate.failure?

        change_set_id, attempt_id = relationships.value!
        work_item_id = target_stream.stream_id
        candidate_event = candidate.value!
        candidate_id = candidate_event.stream_id
        Success([
          build(
            target_stream:,
            event: Events::WorkItemCandidateSelectedV2.new(
              work_item_id:,
              change_set_id:,
              attempt_id:,
              candidate_id:,
              candidate_event:
            ),
            markers: markers(work_item_id, change_set_id:, attempt_id:) + [ "candidate:#{candidate_id}" ],
            step_name: "select-work-item-candidate",
            source_event:
          )
        ])
      end

      def transform_dependency_satisfaction(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        change_set = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentPlanning",
          source_name: "ChangeSet",
          source_id: source.change_set_id,
          target_context: "DevelopmentPlanning",
          target_name: "ChangeSet",
          identity_role: "change-set"
        )
        return change_set if change_set.failure?

        producer = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentExecution",
          source_name: "WorkItem",
          source_id: source.producer_work_item_id,
          target_context: "DevelopmentExecution",
          target_name: "WorkItem",
          identity_role: "work-item"
        )
        return producer if producer.failure?

        step_name = SOURCE_REFERENCE_STEPS[source.source.type]
        return Failure(unsupported_reference(source_event, source.source)) unless step_name

        source_reference = @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.source,
          target_stream_context: "DevelopmentExecution",
          target_stream_name: "WorkItem",
          identity_role: "work-item",
          target_event_type: source.source.type,
          target_step_name: step_name
        )
        return source_reference if source_reference.failure?

        change_set_id = change_set.value!.target_stream.stream_id
        producer_work_item_id = producer.value!.target_stream.stream_id
        consumer_work_item_id = target_stream.stream_id
        Success([
          build(
            target_stream:,
            event: Events::WorkItemDependencySatisfiedV2.new(
              dependency_id: source.dependency_id,
              change_set_id:,
              producer_work_item_id:,
              consumer_work_item_id:,
              dependency_kind: source.dependency_kind,
              required_output: source.required_output,
              source: source_reference.value!
            ),
            markers: [
              "change-set:#{change_set_id}",
              "dependency:#{source.dependency_id}",
              "work-item:#{producer_work_item_id}",
              "work-item:#{consumer_work_item_id}"
            ],
            step_name: "satisfy-work-item-dependency",
            source_event:
          )
        ])
      end

      def resolve_change_set_and_attempt(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        change_set_id:,
        attempt_id:
      )
        change_set = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentPlanning",
          source_name: "ChangeSet",
          source_id: change_set_id,
          target_context: "DevelopmentPlanning",
          target_name: "ChangeSet",
          identity_role: "change-set"
        )
        return change_set if change_set.failure?

        attempt = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentExecution",
          source_name: "Attempt",
          source_id: attempt_id,
          target_context: "DevelopmentExecution",
          target_name: "Attempt",
          identity_role: "attempt"
        )
        return attempt if attempt.failure?

        Success([
          change_set.value!.target_stream.stream_id,
          attempt.value!.target_stream.stream_id
        ])
      end

      def with_change_set(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_id:
      )
        result = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentPlanning",
          source_name: "ChangeSet",
          source_id:,
          target_context: "DevelopmentPlanning",
          target_name: "ChangeSet",
          identity_role: "change-set"
        )
        return result if result.failure?

        Success([ yield(result.value!.target_stream.stream_id) ])
      end

      def resolve_entity(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_context:,
        source_name:,
        source_id:,
        target_context:,
        target_name:,
        identity_role:
      )
        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: source_context,
            stream_name: source_name,
            stream_id: source_id
          ),
          target_stream_context: target_context,
          target_stream_name: target_name,
          identity_role:
        )
      end

      def build(target_stream:, event:, markers:, step_name:, source_event:)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension: metadata_extension(source_event)
        )
      end

      def metadata_extension(source_event)
        MigrationMetadataExtensionV1.new(
          attributed_actor: Commands::Actor.new(
            kind: source_event.metadata.fetch("actor_kind"),
            id: source_event.metadata.fetch("actor_id")
          ),
          policy_version: source_event.metadata["policy_version"]
        )
      end

      def markers(work_item_id, change_set_id: nil, attempt_id: nil)
        [
          "work-item:#{work_item_id}",
          ("change-set:#{change_set_id}" if change_set_id),
          ("attempt:#{attempt_id}" if attempt_id)
        ].compact
      end

      def unsupported_reference(source_event, source_reference)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Unsupported WorkItem dependency source type #{source_reference.type}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
