# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteDeclareDevelopmentArtifactRelation < Dry::Operation
      TOOL_NAME = "development_artifact_relation_declare"

      def initialize(
        event_store:,
        preparer: PrepareDeclareDevelopmentArtifactRelation.new,
        loader: DevelopmentArtifacts::Loader.new(event_store:),
        target_resolver: DevelopmentArtifacts::RelationTargetResolver.new(event_store:),
        decider: Domain::DevelopmentArtifacts::DeclareRelationV2.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        marker_builder: DevelopmentArtifacts::MarkerBuilder.new,
        completion_builder: CommandResultBuilder.new
      )
        @event_store = event_store
        @preparer = preparer
        @loader = loader
        @target_resolver = target_resolver
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @marker_builder = marker_builder
        @completion_builder = completion_builder
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
        DevelopmentArtifactRelationPreparationV1.new(
          declared_at: @clock.now,
          input_digest: @input_digest.development_artifact_relation_declare(command),
          domain_event_ids: [ @id_generator.uuid_v7, @id_generator.uuid_v7 ],
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        resolved = resolve_relation(command)
        return resolved if resolved.failure?

        command = resolved.value!

        artifact_relation = command.artifact_relation
        target = @target_resolver.call(
          source_artifact_id: artifact_relation.source_artifact_id,
          target: artifact_relation.target
        )
        return target if target.failure?

        source_state = @loader.load(artifact_relation.source_artifact_id)
        unless source_state.created
          return Failure(OutcomeError.new(
            code: :development_artifact_not_found,
            message: "Source Development Artifact was not found",
            details: { artifact_id: artifact_relation.source_artifact_id }
          ))
        end
        command = with_target(command, target.value!)
        source_relations = load_relation_states(artifact_relation.source_artifact_id)
        superseded_state = command.supersedes_relation_id && source_relations.find do |state|
          state.declaration&.relation_id == command.supersedes_relation_id
        end
        decision_result = @decider.call(
          relation: command.artifact_relation,
          source_relations:,
          superseded_state:,
          superseded_relation_id: command.supersedes_relation_id,
          supersession_reason: command.supersession_reason
        )
        return decision_result if decision_result.failure?

        decision = decision_result.value!
        persisted_events = persist_domain_plan(
          decision.event_plan,
          command:,
          event_ids: preparation.domain_event_ids,
          caused_by:
        )
        completion = @completion_builder.development_artifact_relation_declare(
          command:,
          decision:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.declared_at
        )

        Success(completion)
      end

      def resolve_relation(command)
        proposed = command.artifact_relation
        events = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentMemory",
            stream_name: "DevelopmentArtifactRelation",
            event_types: [ "DevelopmentArtifactRelationDeclared" ],
            markers: [ @marker_builder.relation_natural_key(proposed) ],
            maximum_count: 1,
            direction: :asc
          )
        )
        return Success(command) if events.empty?

        declaration = load_event(events.sole)
        return relation_registry_invalid(proposed) unless declaration.is_a?(Events::DevelopmentArtifactRelationDeclaredV2)

        Success(with_relation_id(command, declaration.relation_id))
      rescue EventHistoryLimitExceeded, EventSchemaRegistry::UnknownSchema,
             EventSchemaRegistry::SchemaMismatch, Dry::Struct::Error, KeyError, ArgumentError
        relation_registry_invalid(proposed)
      end

      def with_relation_id(command, relation_id)
        original = command.artifact_relation
        relation = DevelopmentArtifacts::RelationV1.new(
          relation_id:,
          source_artifact_id: original.source_artifact_id,
          relation: original.relation,
          target: original.target,
          attributes: original.relation_attributes
        )
        values = {
          command_id: command.command_id,
          actor: command.actor,
          artifact_relation: relation
        }
        values[:supersedes_relation_id] = command.supersedes_relation_id if command.supersedes_relation_id
        values[:supersession_reason] = command.supersession_reason if command.supersession_reason
        Commands::DeclareDevelopmentArtifactRelation.new(**values)
      end

      def relation_registry_invalid(relation)
        Failure(
          OutcomeError.new(
            code: :development_artifact_relation_registry_invalid,
            message: "Development Artifact relation natural key is inconsistent",
            details: { relation_id: relation.relation_id }
          )
        )
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist_domain_plan(plan, command:, event_ids:, caused_by:)
        return [] unless plan

        artifact_relation = command.artifact_relation
        unless plan.writes.length.between?(1, 2) && plan.writes.all? do |write|
          write.stream.stream_name == "DevelopmentArtifactRelation"
        end
          raise "DeclareDevelopmentArtifactRelation domain plan must write one or two relation events"
        end

        persisted_writes = plan.writes.zip(event_ids).map do |write, event_id|
          event = write.event
          [ write.stream, @event_factory.build!(
            event:,
            event_id:,
            metadata: command_metadata(command),
            markers: event_markers(event, artifact_relation:, command_id: command.command_id),
            caused_by:
          ) ]
        end
        persisted_writes.map do |stream, event|
          @event_store.append(stream, [ event ]).sole
        end
      end

      def event_markers(event, artifact_relation:, command_id:)
        case event
        when Events::DevelopmentArtifactRelationDeclaredV2
          @marker_builder.relation(artifact_relation:, command_id:)
        when Events::DevelopmentArtifactRelationSupersededV2
          @marker_builder.supersession(event:, command_id:)
        else
          raise "Unexpected Development Artifact relation event #{event.class.name}"
        end
      end

      def load_relation_states(source_artifact_id)
        events = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentMemory",
            stream_name: "DevelopmentArtifactRelation",
            event_types: [
              "DevelopmentArtifactRelationDeclared",
              "DevelopmentArtifactRelationSuperseded"
            ],
            markers: [ "development-artifact:#{source_artifact_id}" ],
            maximum_count: Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT * 2,
            direction: :asc
          )
        )
        events.group_by { _1.stream.stream_id }.values.map do |relation_events|
          Domain::DevelopmentArtifacts::RelationStateV2.reduce(relation_events.map { load_event(_1) })
        end
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "development-artifact-repository/v2"
        )
      end

      def with_target(command, target)
        Commands::DeclareDevelopmentArtifactRelation.new(
          command.to_h.merge(artifact_relation: command.artifact_relation.with_target(target))
        )
      end
    end
  end
end
