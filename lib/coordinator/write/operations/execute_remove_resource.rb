# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRemoveResource < Dry::Operation
      TOOL_NAME = "resource_remove"

      class InputContract < Dry::Validation::Contract
        config.validate_keys = true

        params do
          required(:command_id).filled(:string)
          required(:actor).hash do
            required(:kind).filled(:string, included_in?: [ "agent" ])
            required(:id).filled(:string)
          end
          required(:resource_id).filled(:string)
          required(:reason).filled(:string, included_in?: %w[removed renamed type_changed])
        end

        rule(:command_id) do
          key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
        end

        rule(:actor) do
          key([ :actor, :id ]).failure("must be a valid identifier") unless
            Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
        end

        rule(:resource_id) do
          key.failure("must be a UUIDv7 Resource ID") unless Types::UUID_V7_PATTERN.match?(value)
        end
      end

      class PreparationV1 < Value
        attribute :removed_at, Types::Timestamp
        attribute :input_digest, Types::Sha256Digest
        attribute :unbinding_event_id, Types::UuidV7
      end

      class RegisteredIdentityV1 < Value
        attribute :registration, Events::ResourceIdentityV1::Registration
        attribute :identity, ResourceIdentityV1
      end

      def initialize(
        event_store:,
        contract: InputContract.new,
        normalizer: ResourceIdentityNormalizer.new,
        decider: Domain::Resources::Remove.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new
      )
        @event_store = event_store
        @contract = contract
        @normalizer = normalizer
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def prepare(input)
        result = @contract.call(input)
        return invalid_input(result.errors.to_h) if result.failure?

        attributes = result.to_h
        actor = attributes.fetch(:actor)
        Success(
          Commands::RemoveResource.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            resource_id: attributes.fetch(:resource_id),
            reason: attributes.fetch(:reason)
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
            removed_at: @clock.now,
            input_digest: @input_digest.call(command),
            unbinding_event_id: @id_generator.uuid_v7,
          )

          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def execute_attempt(command:, preparation:, caused_by:)
        registered = step load_registered_identity(command.resource_id)
        current_binding = step load_current_binding(
          registered.identity,
          resource_id: command.resource_id
        )
        decision = @decider.call(
          registration: registered.registration,
          current_binding:,
          reason: command.reason,
          removed_at: preparation.removed_at
        )
        return decision if decision.failure?

        removal = decision.value!
        persisted = persist_resource_events(
          removal,
          identity: registered.identity,
          command:,
          event_id: preparation.unbinding_event_id,
          caused_by:
        )
        completion = build_completion(
          command:,
          removal:,
          input_digest: preparation.input_digest,
          persisted_events: persisted,
          completed_at: preparation.removed_at
        )

        Success(completion)
      end

      def load_registered_identity(resource_id)
        event = @event_store.read(
          @stream_factory.resource(resource_id),
          EventReadCriteria.new(
            event_types: [ "ResourceRegistered" ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        return resource_not_found(resource_id) unless event

        registration = deserialize(event)
        identity_result = @normalizer.call(
          repository_id: registration.repository_id,
          kind: registration.kind,
          path: registration.normalized_path
        )
        return corrupt(resource_id, "registration_identity_invalid") if identity_result.failure?

        identity = identity_result.value!
        return corrupt(resource_id, "registration_stream_mismatch") unless
          event.stream.stream_id == resource_id && registration.resource_id == resource_id
        return corrupt(resource_id, "registration_revision_mismatch") unless event.stream_revision.zero?
        return corrupt(resource_id, "registration_marker_mismatch") unless
          event.markers.include?(identity.identity_marker)

        canonical_event = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: event.stream.context,
            stream_name: event.stream.stream_name,
            event_types: [ "ResourceRegistered" ],
            markers: [ identity.identity_marker ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        return corrupt(resource_id, "registration_global_mismatch") unless
          canonical_event&.id == event.id

        Success(RegisteredIdentityV1.new(registration:, identity:))
      rescue EventHistoryLimitExceeded
        corrupt(resource_id, "duplicate_registration")
      rescue KeyError, Dry::Struct::Error
        corrupt(resource_id, "registration_schema_invalid")
      end

      def load_current_binding(identity, resource_id:)
        resource_stream = @stream_factory.resource(resource_id)
        event = @event_store.read_latest_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: resource_stream.context,
            stream_name: resource_stream.stream_name,
            event_types: [ "ResourceBound", "ResourceUnbound" ],
            markers: [ identity.current_path_marker ],
            maximum_count: 1,
            direction: :desc
          )
        )
        return Success(nil) unless event

        binding = deserialize(event)
        return corrupt(resource_id, "binding_marker_mismatch") unless
          event.markers.include?(identity.current_path_marker)
        return corrupt(resource_id, "binding_stream_mismatch") unless
          event.stream.stream_id == binding.resource_id
        return corrupt(resource_id, "binding_identity_mismatch") unless
          binding.repository_id == identity.repository_id &&
          binding.normalized_path == identity.normalized_path

        Success(binding)
      rescue KeyError, Dry::Struct::Error
        corrupt(resource_id, "binding_schema_invalid")
      end

      def resource_not_found(resource_id)
        Failure(
          OutcomeError.new(
            code: :resource_not_found,
            message: "Resource is not registered",
            details: { resource_id: }
          )
        )
      end

      def corrupt(resource_id, reason)
        Failure(
          OutcomeError.new(
            code: :resource_history_corrupt,
            message: "Resource identity history is inconsistent",
            details: { resource_id:, reason: }
          )
        )
      end

      def invalid_input(details)
        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "RemoveResource input is invalid",
            details:
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

      def persist_resource_events(removal, identity:, command:, event_id:, caused_by:)
        return [] if removal.events.empty?

        payload = removal.events.sole
        event = @event_factory.build!(
          event: payload,
          event_id:,
          metadata: command_metadata(command),
          markers: [
            identity.identity_marker,
            identity.current_path_marker,
            "resource:#{payload.resource_id}",
            "repository:#{payload.repository_id}",
            "command:#{command.command_id}"
          ],
          caused_by:
        )
        @event_store.append(@stream_factory.resource(payload.resource_id), [ event ])
      end

      def build_completion(command:, removal:, input_digest:, persisted_events:, completed_at:)
        registration = removal.registration
        CommandResultV1.new(
          command_id: command.command_id,
          tool_name: TOOL_NAME,
          canonical_input_digest: input_digest,
          status: "ok",
          summary: removal_summary(removal.outcome),
          receipt: command.command_id,
          data: CommandReceiptData::ResourceRemoval.new(
            resource_id: registration.resource_id,
            repository_id: registration.repository_id,
            kind: registration.kind,
            normalized_path: registration.normalized_path,
            outcome: removal.outcome,
            reason: command.reason,
            unbound_at: removal.unbound_at
          ),
          warnings: [],
          next_actions: [],
          emitted_events: persisted_events.map { event_reference(_1) },
          completed_at:
        )
      end

      def removal_summary(outcome)
        case outcome
        when "removed" then "Resource binding removed."
        when "already_inactive" then "Resource binding was already inactive."
        else "Resource binding was already superseded."
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
