# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class RelationTargetResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def call(source_artifact_id:, target:)
        return Success(external_target(target)) if target.kind == "external"

        event = target_event(target)
        return Failure(target_missing(source_artifact_id, target)) unless event

        Success(verified_target(target, event))
      end

      private

      def external_target(target)
        RelationTargetV1.new(kind: target.kind, id: target.id, status: "unverified")
      end

      def verified_target(target, event)
        values = { kind: target.kind, id: target.id, status: "verified" }
        if target.kind == "skill"
          publication = load_event(event)
          values[:name] = publication.name
          values[:scope] = publication.scope
        end
        RelationTargetV1.new(**values)
      end

      def target_event(target)
        query = target_query(target)
        return unless query

        stream, criteria, grouped = query
        events = grouped ? @event_store.read_grouped(stream, criteria) : @event_store.read(stream, criteria)
        events.first
      end

      def target_query(target)
        case target.kind
        when "artifact"
          [ @stream_factory.development_artifact(target.id), EventQueries::DEVELOPMENT_ARTIFACT_CAPTURE, false ]
        when "change_set"
          [ @stream_factory.change_set(target.id), EventQueries::CHANGE_SET_EXISTENCE, true ]
        when "work_item"
          [ @stream_factory.work_item(target.id), EventQueries::WORK_ITEM_EXISTENCE, true ]
        when "attempt"
          [ @stream_factory.attempt(target.id), EventQueries::ATTEMPT_FOR_AGENT_CHOICE, false ]
        when "candidate"
          [ @stream_factory.candidate(target.id), EventQueries::CANDIDATE_EXISTENCE, false ]
        when "decision"
          [ @stream_factory.decision(target.id), EventQueries::DECISION_EXISTENCE, false ]
        when "skill"
          [ @stream_factory.skill(target.id), EventQueries::SKILL_LATEST_REVISION, true ]
        when "repository"
          [ @stream_factory.repository(target.id), EventQueries::REPOSITORY_REGISTRATION, false ]
        when "operation_batch"
          [ @stream_factory.operation_batch(target.id), EventQueries::OPERATION_BATCH_EXISTENCE, false ]
        end
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def target_missing(source_artifact_id, target)
        OutcomeError.new(
          code: :development_artifact_target_not_found,
          message: "Development Artifact relationship target was not found",
          details: {
            artifact_id: source_artifact_id,
            target_kind: target.kind,
            target_id: target.id
          }
        )
      end
    end
  end
end
