# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class SkillsV1
      PROJECTION = ProjectionDefinition.new(name: "skills", version: 3)

      def initialize(
        contract: Contracts::SkillSourceEvent.new,
        publication_loader: Coordinator::Write::Skills::PersistedPublicationLoader.new,
        skills: Repositories::Skills.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @publication_loader = publication_loader
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

        publication = @publication_loader.call(event)
        raise InvalidProjectionSource, publication.failure.to_h.inspect if publication.failure?

        publication.value!
      end

      def verify_stream_identity!(event, publication)
        matches = event.stream.stream_id == publication.skill_id &&
                  event.stream_revision + 1 == publication.revision
        return if matches

        raise InvalidProjectionSource, "Skill identity or logical revision does not match its source stream"
      end
    end
  end
end
