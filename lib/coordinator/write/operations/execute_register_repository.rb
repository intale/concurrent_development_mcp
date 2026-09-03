# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRegisterRepository < Dry::Operation
      TOOL_NAME = "repository_register"
      REPOSITORY_EVENT_TYPES = %w[
        RepositoryRegistered
        RepositoryDisplayNameChanged
        RepositoryPathAdded
        RepositoryPathRemoved
        RepositoryRemoteAdded
        RepositoryRemoteRemoved
      ].freeze

      class PreparationV1 < Value
        attribute :input_digest, Types::Sha256Digest
        attribute :event_ids, Types::Array.of(Types::UuidV7).constrained(min_size: 1, max_size: 42)
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
          input_digest: @input_digest.call(command),
          event_ids: Array.new(command_event_count(command)) { @id_generator.uuid_v7 },
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
        registration_by_key_source = load_registration_by_key(command)
        registration_by_id_source = load_registration(command.repository_id)
        registration_by_key = registration_by_key_source&.last
        registration_by_id = registration_by_id_source&.last
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: "repository_register_dcb",
          command_id: command.command_id
        )
        decision = @decider.call(
          registration_by_key:,
          registration_by_id:,
          command:
        )
        return decision if decision.failure?

        decided = decision.value!
        persisted = if decided.event_plan
                      persist_registration(
                        decided.event_plan,
                        command:,
                        caused_by:,
                        event_ids: preparation.event_ids
                      )
                    end
        completion = build_completion(
          command:,
          input_digest: preparation.input_digest,
          registration: decided.registration,
          outcome: decided.outcome,
          persisted_events: persisted || [],
          source_event: registration_by_key_source&.first || registration_by_id_source&.first
        )

        Success(completion)
      end

      def load_registration(repository_id)
        events = @event_store.read(
          @stream_factory.repository(repository_id),
          EventReadCriteria.new(
            event_types: REPOSITORY_EVENT_TYPES,
            maximum_count: 1_024,
            direction: :asc
          )
        )
        fold_registration(events)
      end

      def load_registration_by_key(command)
        event = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentPlanning",
            stream_name: "Repository",
            event_types: [ "RepositoryRegistered" ],
            markers: [ scoped_repository_key_marker(command).marker ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        return unless event

        load_registration(event.stream.stream_id)
      end

      def fold_registration(events)
        registration_event = events.find { _1.type == "RepositoryRegistered" }
        return unless registration_event

        state = nil
        events.each do |event|
          payload = @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          )
          state = case payload
          when Events::RepositoryRegisteredV1
            RepositoryRegistrationV2.new(
              repository_id: payload.repository_id,
              scope: payload.scope,
              repository_key: payload.repository_key,
              display_name: payload.display_name,
              paths: payload.paths,
              remotes: payload.remotes
            )
          when Events::RepositoryRegisteredV2
            RepositoryRegistrationV2.new(
              repository_id: payload.repository_id,
              scope: payload.scope,
              repository_key: payload.repository_key,
              display_name: nil,
              paths: [],
              remotes: []
            )
          when Events::RepositoryDisplayNameChangedV1
            replace_registration(state, display_name: payload.display_name)
          when Events::RepositoryPathAddedV1
            replace_registration(state, paths: (state.paths + [ payload.path ]).uniq)
          when Events::RepositoryPathRemovedV1
            replace_registration(state, paths: state.paths - [ payload.path ])
          when Events::RepositoryRemoteAddedV1
            replace_registration(state, remotes: (state.remotes + [ payload.remote ]).uniq)
          when Events::RepositoryRemoteRemovedV1
            replace_registration(state, remotes: state.remotes - [ payload.remote ])
          else
            state
          end
        end

        [ registration_event, state ]
      end

      def replace_registration(state, attributes)
        RepositoryRegistrationV2.new(state.to_h.merge(attributes))
      end

      def persist_registration(plan, command:, caused_by:, event_ids:)
        writes = plan.writes.each_with_index.map do |write, index|
          @event_factory.build!(
            event: write.event,
            event_id: event_ids.fetch(index),
            metadata: command_metadata(command),
            markers: registration_markers(command, event: write.event),
            caused_by:
          )
        end
        @event_store.append(plan.writes.first.stream, writes)
      end

      def command_event_count(command)
        1 + (command.display_name ? 1 : 0) + command.paths.length + command.remotes.length
      end

      def registration_markers(command, event: nil)
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

        markers = [
          "repository:#{command.repository_id}",
          "repository-key:#{command.repository_key}",
          "command:#{command.command_id}"
        ]
        if event.is_a?(Events::RepositoryRegisteredV2)
          markers.concat([ scope.marker, identity.marker, scoped_key.marker ])
        end
        markers
      end

      def scoped_repository_key_marker(command)
        @natural_key_marker.call(
          scope: command.scope,
          repository_key: command.repository_key
        )
      end

      def build_completion(command:, input_digest:, registration:, outcome:, persisted_events:, source_event:)
        event = persisted_events.first || source_event
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
            registered_at: event.created_at.utc.iso8601(6)
          ),
          warnings: [],
          next_actions: [],
          emitted_events: persisted_events.map { event_reference(_1) },
          completed_at: event.created_at.utc.iso8601(6)
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
