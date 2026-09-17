# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelCandidateContextResolver
      include Dry::Monads[:result]

      SOURCE_TYPES = %w[
        CandidateCreated CandidateAssignedToAttempt CandidateAssignedToRepository
        CandidateTargetBranchSelected CandidateCommitRangeDeclared CandidateCheckpointKindSelected
        CandidateWorkIntentionSetAssigned CandidateChangeManifestCaptured CandidateSubmitted
      ].freeze
      SOURCE_HISTORY = EventReadCriteria.new(
        event_types: SOURCE_TYPES,
        maximum_count: SOURCE_TYPES.length,
        direction: :asc
      )

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        schema_registry: SourceEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @schema_registry = schema_registry
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_candidate_id:
      )
        source_stream = StreamReference.new(
          context: "DevelopmentIntegration",
          stream_name: "Candidate",
          stream_id: source_candidate_id
        )
        facts = load_facts(source_stream, source_upper_position:)
        created = fetch(facts, Events::CandidateCreatedV1)
        assignment = fetch(facts, Events::CandidateAssignedToAttemptV1)
        repository = fetch(facts, Events::CandidateAssignedToRepositoryV1)
        commit_range = fetch(facts, Events::CandidateCommitRangeDeclaredV1)
        intention_set = fetch(facts, Events::CandidateWorkIntentionSetAssignedV1)
        unless created && assignment && repository && commit_range && intention_set &&
            created.last.candidate_id == source_candidate_id
          return Failure(incomplete(source_event, source_candidate_id:))
        end

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: created.first,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "Candidate",
          identity_role: "candidate"
        )
        return allocation if allocation.failure?

        resolved = resolve_relationships(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          assignment: assignment.last,
          repository: repository.last,
          intention_set: intention_set.last
        )
        return resolved if resolved.failure?

        target_ids = resolved.value!
        Success(
          PostRemodelCandidateContextV1.new(
            source_candidate_id:,
            source_change_set_id: assignment.last.change_set_id,
            source_work_item_id: assignment.last.work_item_id,
            source_attempt_id: assignment.last.attempt_id,
            source_repository_id: repository.last.repository_id,
            source_intention_set_id: intention_set.last.intention_set_id,
            candidate_stream: allocation.value!.target_stream,
            candidate_id: allocation.value!.target_stream.stream_id,
            change_set_id: target_ids.fetch(:change_set_id),
            work_item_id: target_ids.fetch(:work_item_id),
            attempt_id: target_ids.fetch(:attempt_id),
            repository_id: target_ids.fetch(:repository_id),
            intention_set_id: target_ids.fetch(:intention_set_id),
            object_format: commit_range.last.object_format,
            head_commit_oid: commit_range.last.head_commit_oid
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(incomplete(source_event, source_candidate_id:, detail: error.message))
      end

      private

      def load_facts(source_stream, source_upper_position:)
        @event_store.read(source_stream, SOURCE_HISTORY).filter_map do |event|
          next if event.global_position > source_upper_position

          [
            event,
            @schema_registry.load(
              type: event.type,
              schema_version: event.metadata.fetch("schema_version"),
              data: event.data
            )
          ]
        end
      end

      def fetch(facts, type)
        facts.find { _1.last.is_a?(type) }
      end

      def resolve_relationships(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        assignment:,
        repository:,
        intention_set:
      )
        definitions = {
          change_set_id: [ "DevelopmentPlanning", "ChangeSet", assignment.change_set_id, "change-set" ],
          work_item_id: [ "DevelopmentExecution", "WorkItem", assignment.work_item_id, "work-item" ],
          attempt_id: [ "DevelopmentExecution", "Attempt", assignment.attempt_id, "attempt" ],
          repository_id: [ "DevelopmentPlanning", "Repository", repository.repository_id, "repository" ],
          intention_set_id: [
            "DevelopmentCoordination",
            "WorkIntentionSet",
            intention_set.intention_set_id,
            "work-intention-set"
          ]
        }
        values = {}
        definitions.each do |key, (context, name, source_id, role)|
          resolved = @entity_reference_resolver.call(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_stream: StreamReference.new(context:, stream_name: name, stream_id: source_id),
            target_stream_context: context,
            target_stream_name: name,
            identity_role: role
          )
          return resolved if resolved.failure?

          values[key] = resolved.value!.target_stream.stream_id
        end
        Success(values.freeze)
      end

      def incomplete(source_event, source_candidate_id:, detail: nil)
        suffix = detail ? ": #{detail}" : ""
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Post-remodel Candidate #{source_candidate_id} has incomplete frozen context#{suffix}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
