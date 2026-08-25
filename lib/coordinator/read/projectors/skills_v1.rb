# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class SkillsV1
      PROJECTION = ProjectionDefinition.new(name: "skills", version: 1)

      def initialize(
        contract: Contracts::SkillSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        identity_builder: Coordinator::Write::Skills::IdentityBuilder.new,
        skills: Repositories::Skills.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
        @identity_builder = identity_builder
        @skills = skills
        @processed_events = processed_events
      end

      def call(event)
        publication = load_publication(event)
        verify_stream_identity!(event, publication)
        identity = ProjectionEventIdentity.from_event(event)

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: Time.now.utc
          )

          @skills.store_revision(event:, publication:)
        end

        nil
      end

      private

      def load_publication(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          global_position: event.global_position,
          command_id: event.metadata["command_id"],
          actor_kind: event.metadata["actor_kind"],
          actor_id: event.metadata["actor_id"],
          recorded_by: event.metadata["recorded_by"],
          policy_version: event.metadata["policy_version"]
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify_stream_identity!(event, publication)
        identity = @identity_builder.call(name: publication.name, scope: publication.scope)
        matches = event.stream.stream_id == publication.skill_id &&
                  identity.skill_id == publication.skill_id &&
                  event.stream_revision + 1 == publication.revision
        return if matches

        raise InvalidProjectionSource, "Skill identity or logical revision does not match its source stream"
      end
    end
  end
end
