# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRegisterRepository < Dry::Operation
      TOOL_NAME = "repository_register"

      class PreparationV1 < Value
        attribute :registered_at, Types::Timestamp
        attribute :input_digest, Types::Sha256Digest
        attribute :domain_event_id, Types::UuidV7
      end

      def initialize(
        event_store:,
        contract: Contracts::RegisterRepository.new,
        decider: Domain::Repositories::Register.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        compound_marker_builder: CompoundMarkerBuilder.new,
        natural_key_marker: Repositories::NaturalKeyMarker.new
      )
        @event_store = event_store
        @contract = contract
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @compound_marker_builder = compound_marker_builder
        @natural_key_marker = natural_key_marker
      end

      def prepare(input)
        result = @contract.call(input)
        return invalid_input(result.errors.to_h) if result.failure?

        attributes = result.to_h
        actor = attributes.fetch(:actor)
        Success(
          Commands::RegisterRepository.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            repository_id: attributes.fetch(:repository_id),
            scope: attributes.fetch(:scope),
            repository_key: attributes.fetch(:repository_key),
            display_name: attributes[:display_name],
            paths: attributes.fetch(:paths),
            remotes: attributes.fetch(:remotes)
          )
        )
      end

      def call(input)
        command = step prepare(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        preparation = PreparationV1.new(
          registered_at: @clock.now,
          input_digest: @input_digest.call(command),
          domain_event_id: @id_generator.uuid_v7,
        )

        @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
      end

      private

      def invalid_input(details)
        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "RegisterRepository input is invalid",
            details:
          )
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        registration_by_key = load_registration_by_key(command)
        registration_by_id = load_registration(command.repository_id)
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: "repository_register_dcb",
          command_id: command.command_id
        )
        decision = @decider.call(
          registration_by_key:,
          registration_by_id:,
          command:,
          registered_at: preparation.registered_at
        )
        return decision if decision.failure?

        decided = decision.value!
        persisted = if decided.event_plan
                      persist_registration(
                        decided.event_plan,
                        command:,
                        event_id: preparation.domain_event_id,
                        caused_by:
                      )
        end
        completion = build_completion(
          command:,
          input_digest: preparation.input_digest,
          registration: decided.registration,
          outcome: decided.outcome,
          persisted_event: persisted,
          completed_at: preparation.registered_at
        )

        Success(completion)
      end

      def load_registration(repository_id)
        event = @event_store.read(
          @stream_factory.repository(repository_id),
          EventReadCriteria.new(
            event_types: [ "RepositoryRegistered" ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        deserialize(event)
      end

      def load_registration_by_key(command)
        repository_stream = @stream_factory.repository(command.repository_id)
        event = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: repository_stream.context,
            stream_name: repository_stream.stream_name,
            event_types: [ "RepositoryRegistered" ],
            markers: [ scoped_repository_key_marker(command).marker ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        deserialize(event)
      end

      def deserialize(event)
        return unless event

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist_registration(plan, command:, event_id:, caused_by:)
        write = plan.writes.sole

        event = @event_factory.build!(
          event: write.event,
          event_id:,
          metadata: command_metadata(command),
          markers: registration_markers(command),
          caused_by:
        )
        @event_store.append(write.stream, [ event ]).fetch(0)
      end

      def registration_markers(command)
        scope = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "repository-scope",
            components: [ "dimension:scope", "scope:#{command.scope}" ]
          )
        )
        identity = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "scoped-repository",
            components: [ "scope:#{command.scope}", "repository:#{command.repository_id}" ]
          )
        )
        scoped_key = scoped_repository_key_marker(command)

        [
          "repository:#{command.repository_id}",
          "repository-key:#{command.repository_key}",
          scope.marker,
          identity.marker,
          scoped_key.marker,
          "command:#{command.command_id}"
        ]
      end

      def scoped_repository_key_marker(command)
        @natural_key_marker.call(
          scope: command.scope,
          repository_key: command.repository_key
        )
      end

      def build_completion(command:, input_digest:, registration:, outcome:, persisted_event:, completed_at:)
        CommandResultV1.new(
          command_id: command.command_id,
          tool_name: TOOL_NAME,
          canonical_input_digest: input_digest,
          status: "ok",
          summary: outcome == "registered" ?
            "Repository registered under its exact coordination scope and key." :
            "Canonical Repository registration already exists for the exact scope and key.",
          receipt: command.command_id,
          data: CommandReceiptData::RepositoryRegistration.new(
            repository_id: registration.repository_id,
            scope: registration.scope,
            display_name: registration.display_name,
            paths: registration.paths,
            remotes: registration.remotes,
            registered_at: registration.registered_at
          ),
          warnings: [],
          next_actions: [],
          emitted_events: persisted_event ? [ event_reference(persisted_event) ] : [],
          completed_at:
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

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "repository-registration/v1"
        )
      end
    end
  end
end
