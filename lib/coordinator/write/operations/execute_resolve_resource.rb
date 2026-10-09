# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteResolveResource < Dry::Operation
      TOOL_NAME = "resource_resolve"

      class InputContract < Dry::Validation::Contract
        config.validate_keys = true

        params do
          required(:command_id).filled(:string)
          required(:actor).hash do
            required(:kind).filled(:string, included_in?: [ "agent" ])
            required(:id).filled(:string)
          end
          required(:repository_id).filled(:string)
          required(:kind).filled(:string)
          required(:path).filled(:string)
        end

        rule(:command_id) do
          key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
        end

        rule(:actor) do
          key([ :actor, :id ]).failure("must be a valid identifier") unless
            Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
        end
      end

      class PreparationV1 < Value
        attribute :input_digest, Types::Sha256Digest
        attribute :proposed_resource_id, Types::ResourceId
        attribute :registration_event_id, Types::UuidV7
        attribute :binding_event_id, Types::UuidV7
      end

      def initialize(
        event_store:,
        contract: InputContract.new,
        normalizer: ResourceIdentityNormalizer.new,
        decider: Domain::Resources::Resolve.new,
        repository_registration_loader: RepositoryRegistrationLoader.new(event_store:),
        input_digest: CommandInputDigest.new,
        resource_id_generator: ResourceIdGenerator.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new
      )
        @event_store = event_store
        @contract = contract
        @normalizer = normalizer
        @decider = decider
        @repository_registration_loader = repository_registration_loader
        @input_digest = input_digest
        @resource_id_generator = resource_id_generator
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def prepare(input)
        result = @contract.call(input)
        return invalid_input(result.errors.to_h) if result.failure?

        attributes = result.to_h
        identity = @normalizer.call(
          repository_id: attributes.fetch(:repository_id),
          kind: attributes.fetch(:kind),
          path: attributes.fetch(:path)
        )
        return invalid_input(identity.failure.details) if identity.failure?

        actor = attributes.fetch(:actor)
        Success(
          Commands::ResolveResource.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            identity: identity.value!
          )
        )
      end

      def call(input)
        command = step prepare(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        steps do
          preparation = PreparationV1.new(
            input_digest: @input_digest.call(command),
            proposed_resource_id: @resource_id_generator.call,
            registration_event_id: @id_generator.uuid_v7,
            binding_event_id: @id_generator.uuid_v7,
          )

          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def invalid_input(details)
        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "ResolveResource input is invalid",
            details:
          )
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        repository = @repository_registration_loader.call(command.repository_id)
        return repository_not_registered(command) unless repository

        registration_source = step load_registration(command.identity)
        registration = registration_source&.last
        current_binding_source = step load_current_binding(command.identity)
        current_binding = current_binding_source&.last

        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: "resource_resolve_dcb",
          command_id: command.command_id
        )

        decision = @decider.call(
          identity: command.identity,
          proposed_resource_id: preparation.proposed_resource_id,
          registration:,
          current_binding:
        )
        return decision if decision.failure?

        resolved = decision.value!
        persisted = persist_resource_events(
          resolved,
          command:,
          preparation:,
          caused_by:
        )
        completion = build_completion(
          command:,
          resolution: resolved,
          input_digest: preparation.input_digest,
          persisted_events: persisted,
          registration_event: registration_source&.first,
          binding_event: current_binding_source&.first
        )

        Success(completion)
      end

      def load_registration(identity)
        event = @event_store.read_global_marked(
          resource_criteria(
            identity:,
            event_types: [ "ResourceRegistered" ],
            marker: identity.identity_marker,
            direction: :asc
          )
        ).first
        return Success(nil) unless event

        registration = deserialize(event)
        return corrupt(identity, "registration_marker_mismatch") unless
          event.markers.include?(identity.identity_marker)
        return corrupt(identity, "registration_stream_mismatch") unless
          event.stream.stream_id == registration.resource_id
        return corrupt(identity, "registration_identity_mismatch") unless
          registration.repository_id == identity.repository_id &&
          registration.kind == identity.kind &&
          registration.normalized_path == identity.normalized_path

        Success([ event, registration ])
      rescue EventHistoryLimitExceeded
        corrupt(identity, "duplicate_registration")
      rescue KeyError, Dry::Struct::Error
        corrupt(identity, "registration_schema_invalid")
      end

      def load_current_binding(identity)
        event = @event_store.read_latest_global_marked(
          resource_criteria(
            identity:,
            event_types: [ "ResourceBound", "ResourceUnbound" ],
            marker: identity.current_path_marker,
            direction: :desc
          )
        )
        return Success(nil) unless event

        binding = deserialize(event)
        return corrupt(identity, "binding_marker_mismatch") unless
          event.markers.include?(identity.current_path_marker)
        return corrupt(identity, "binding_stream_mismatch") unless
          event.stream.stream_id == binding.resource_id
        return corrupt(identity, "binding_identity_mismatch") unless
          binding.repository_id == identity.repository_id &&
          binding.normalized_path == identity.normalized_path
        Success([ event, binding ])
      rescue KeyError, Dry::Struct::Error
        corrupt(identity, "binding_schema_invalid")
      end

      def resource_criteria(identity:, event_types:, marker:, direction:)
        stream = @stream_factory.resource(identity.repository_id)
        GlobalMarkedEventReadCriteria.new(
          stream_context: stream.context,
          stream_name: stream.stream_name,
          event_types:,
          markers: [ marker ],
          maximum_count: 1,
          direction:
        )
      end

      def repository_not_registered(command)
        Failure(
          OutcomeError.new(
            code: :repository_not_registered,
            message: "Repository must be registered before resolving Resources",
            details: { repository_id: command.repository_id }
          )
        )
      end

      def corrupt(identity, reason)
        Failure(
          OutcomeError.new(
            code: :resource_history_corrupt,
            message: "Resource identity history is inconsistent",
            details: {
              repository_id: identity.repository_id,
              kind: identity.kind,
              normalized_path: identity.normalized_path,
              identity_marker: identity.identity_marker,
              current_path_marker: identity.current_path_marker,
              reason:
            }
          )
        )
      end

      def deserialize(event)
        return unless event

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def persist_resource_events(resolution, command:, preparation:, caused_by:)
        return [] if resolution.events.empty?

        events = resolution.events.map do |payload|
          @event_factory.build!(
            event: payload,
            event_id: event_id(payload, preparation),
            metadata: command_metadata(command),
            markers: resource_markers(payload, command),
            caused_by:
          )
        end

        @event_store.append(@stream_factory.resource(resolution.registration.resource_id), events)
      end

      def event_id(payload, preparation)
        case payload
        when Events::ResourceIdentityV2::Registered then preparation.registration_event_id
        when Events::ResourceIdentityV2::Bound then preparation.binding_event_id
        end
      end

      def resource_markers(payload, command)
        markers = [
          command.identity.identity_marker,
          "resource:#{payload.resource_id}",
          "repository:#{command.identity.repository_id}",
          "command:#{command.command_id}"
        ]
        case payload
        when Events::ResourceIdentityV2::Bound, Events::ResourceIdentityV2::Unbound
          markers << command.identity.current_path_marker
        end
        markers
      end

      def build_completion(command:, resolution:, input_digest:, persisted_events:, registration_event:, binding_event:)
        registration_event ||= persisted_events.find { _1.type == "ResourceRegistered" }
        binding_event ||= persisted_events.reverse.find { _1.type == "ResourceBound" }
        CommandResultV1.new(
          command_id: command.command_id,
          tool_name: TOOL_NAME,
          canonical_input_digest: input_digest,
          status: "ok",
          summary: resolution_summary(resolution.outcome),
          receipt: command.command_id,
          data: CommandReceiptData::ResourceResolution.new(
            resource_id: resolution.registration.resource_id,
            repository_id: resolution.registration.repository_id,
            kind: resolution.registration.kind,
            normalized_path: resolution.registration.normalized_path,
            outcome: resolution.outcome,
            registered_at: registration_event.created_at.utc.iso8601(6),
            bound_at: binding_event.created_at.utc.iso8601(6)
          ),
          warnings: [],
          next_actions: [],
          emitted_events: persisted_events.map { event_reference(_1) },
          completed_at: binding_event.created_at.utc.iso8601(6)
        )
      end

      def resolution_summary(outcome)
        case outcome
        when "registered" then "Resource identity registered and bound."
        when "reactivated" then "Existing Resource identity reactivated."
        else "Existing Resource identity resolved."
        end
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
          policy_version: "resource-identity/v1"
        )
      end
    end
  end
end
