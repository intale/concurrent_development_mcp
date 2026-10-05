# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CandidateContextResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        entity_reference_resolver:,
        target_event_reference_resolver:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @schema_registry = schema_registry
      end

      def from_submission(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_candidate:
      )
        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "Candidate",
          identity_role: "candidate"
        )
        return allocation if allocation.failure?

        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_candidate:,
          source_candidate_event: source_event,
          candidate_stream: allocation.value!.target_stream,
          target_submission_event: nil
        )
      end

      def from_stream(migration_id:, source_config_name:, source_upper_position:, source_event:)
        persisted = @event_store.read_at(stream_for(source_event), 0)
        unless persisted && persisted.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "Candidate submission is absent from the frozen source range"))
        end

        source_candidate = load_payload(persisted)
        unless source_candidate.is_a?(Events::CandidateSubmittedV2)
          return Failure(inconsistent(source_event, "Candidate stream does not begin with CandidateSubmitted@2"))
        end

        from_submission(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event: persisted,
          source_candidate:
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, "Candidate submission is invalid: #{error.message}"))
      end

      def from_reference(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:
      )
        source_fact = load_reference(
          source_event:,
          source_upper_position:,
          source_reference:
        )
        return source_fact if source_fact.failure?

        source_candidate = source_fact.value!.payload
        unless source_candidate.is_a?(Events::CandidateSubmittedV2)
          return Failure(inconsistent(source_event, "Candidate reference does not identify CandidateSubmitted@2"))
        end

        target_submission = @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "Candidate",
          identity_role: "candidate",
          target_event_type: "CandidateSubmitted",
          target_step_name: "submit-candidate"
        )
        return target_submission if target_submission.failure?

        target_event = target_submission.value!
        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_candidate:,
          source_candidate_event: source_fact.value!.event,
          candidate_stream: StreamReference.new(
            context: target_event.stream_context,
            stream_name: target_event.stream_name,
            stream_id: target_event.stream_id
          ),
          target_submission_event: target_event
        )
      end

      def load_reference(source_event:, source_upper_position:, source_reference:)
        persisted = @event_store.read_at(
          StreamReference.new(
            context: source_reference.stream_context,
            stream_name: source_reference.stream_name,
            stream_id: source_reference.stream_id
          ),
          source_reference.stream_revision
        )
        unless persisted && persisted.id == source_reference.event_id && persisted.type == source_reference.type &&
            persisted.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "Referenced Candidate evidence is absent from the frozen source range"))
        end

        Success(CandidateSourceFactV1.new(event: persisted, payload: load_payload(persisted)))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, "Referenced Candidate evidence is invalid: #{error.message}"))
      end

      private

      def resolve(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_candidate:,
        source_candidate_event:,
        candidate_stream:,
        target_submission_event:
      )
        change_set = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentPlanning",
          source_name: "ChangeSet",
          source_id: source_candidate.change_set_id,
          target_context: "DevelopmentPlanning",
          target_name: "ChangeSet",
          identity_role: "change-set"
        )
        return change_set if change_set.failure?

        work_item = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentExecution",
          source_name: "WorkItem",
          source_id: source_candidate.work_item_id,
          target_context: "DevelopmentExecution",
          target_name: "WorkItem",
          identity_role: "work-item"
        )
        return work_item if work_item.failure?

        attempt = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentExecution",
          source_name: "Attempt",
          source_id: source_candidate.attempt_id,
          target_context: "DevelopmentExecution",
          target_name: "Attempt",
          identity_role: "attempt"
        )
        return attempt if attempt.failure?

        repository = resolve_entity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_context: "DevelopmentPlanning",
          source_name: "Repository",
          source_id: source_candidate.repository_id,
          target_context: "DevelopmentPlanning",
          target_name: "Repository",
          identity_role: "repository"
        )
        return repository if repository.failure?

        intention_set = resolve_intention_set(
          migration_id:, source_config_name:, source_upper_position:, source_event:, source_candidate:
        )
        return intention_set if intention_set.failure?

        Success(
          CandidateContextV1.new(
            source_candidate:,
            source_candidate_event:,
            target_submission_event:,
            candidate_stream:,
            candidate_id: candidate_stream.stream_id,
            change_set_id: change_set.value!.target_stream.stream_id,
            work_item_id: work_item.value!.target_stream.stream_id,
            attempt_id: attempt.value!.target_stream.stream_id,
            repository_id: repository.value!.target_stream.stream_id,
            intention_set_id: intention_set.value!.target_stream.stream_id
          )
        )
      end

      def resolve_intention_set(migration_id:, source_config_name:, source_upper_position:, source_event:, source_candidate:)
        reservation = @event_store.read_marked(
          StreamReference.new(context: "DevelopmentExecution", stream_name: "Attempt", stream_id: source_candidate.attempt_id),
          MarkedEventReadCriteria.new(
            event_type: "WriteSetReserved", marker: "lease-set:#{source_candidate.lease_set_id}",
            maximum_count: 1, direction: :asc
          )
        ).first
        payload = reservation && load_payload(reservation)
        valid = reservation && reservation.global_position <= source_upper_position &&
                payload.is_a?(Events::WriteSetReservedV2) &&
                payload.lease_set_id == source_candidate.lease_set_id &&
                payload.attempt_id == source_candidate.attempt_id &&
                payload.work_item_id == source_candidate.work_item_id &&
                payload.change_set_id == source_candidate.change_set_id &&
                payload.repository_id == source_candidate.repository_id
        unless valid
          return Failure(inconsistent(source_event, "Candidate work-intention reservation is absent or inconsistent in the frozen source range"))
        end

        @stream_identity_allocator.call(
          migration_id:, source_config_name:, source_event: reservation,
          target_stream_context: "DevelopmentCoordination", target_stream_name: "WorkIntentionSet",
          identity_role: "work-intention-set:#{source_candidate.lease_set_id}"
        )
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

      def load_payload(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def stream_for(event)
        StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message:,
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
