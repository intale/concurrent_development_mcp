# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class SkillPublicationSourceLoader
      def initialize(
        event_store:,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        stream_factory: Coordinator::Write::StreamFactory.new,
        marker_builder: Coordinator::Write::Skills::MarkerBuilder.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @marker_builder = marker_builder
      end

      def call(source)
        command = source.command
        registration = registration_for(command, through_position: source.terminal_event.global_position)
        publications = source.persisted_events.select { _1.type == "SkillRevisionPublished" }
        raise InvalidProjectionSource, "Skill publication command emitted multiple publications" if publications.length > 1

        published = publications.any?
        # The Skill identity stream contains registration at revision 0 and one
        # publication per logical revision. Read the selected revision, not the
        # latest one, so delayed no-op result assembly remains deterministic.
        event = publications.first || @event_store.read_at(
          @stream_factory.skill(registration.skill_id), command.expected_revision
        )
        raise InvalidProjectionSource, "Skill publication source is missing" unless event

        publication = load_payload(event)
        revision = command.expected_revision + (published ? 1 : 0)
        unless publication.is_a?(Coordinator::Write::Events::SkillRevisionPublishedV3) &&
               publication.skill_id == registration.skill_id && publication.revision == revision &&
               skill_stream?(event, registration.skill_id) &&
               event.stream_revision == revision &&
               event.global_position <= source.terminal_event.global_position &&
               event.metadata.fetch("content_digest") == command.content_digest
          raise InvalidProjectionSource, "Skill publication does not match the canonical command source"
        end

        event
      rescue Coordinator::Write::EventHistoryLimitExceeded,
             Coordinator::Write::EventSchemaRegistry::UnknownSchema,
             Coordinator::Write::EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, "Skill publication source is invalid: #{error.message}"
      end

      private

      def registration_for(command, through_position:)
        events = @event_store.read_global_marked(
          Coordinator::Write::GlobalMarkedEventReadCriteria.new(
            stream_context: "AgentKnowledge",
            stream_name: "Skill",
            event_types: [ "SkillRegistered" ],
            markers: [ @marker_builder.natural_key(name: command.name, scope: command.scope) ],
            maximum_count: 1,
            direction: :asc,
            to_position: through_position
          )
        )
        event = events.first
        raise InvalidProjectionSource, "Skill publication registration is missing" unless event

        registration = load_payload(event)
        unless registration.is_a?(Coordinator::Write::Events::SkillRegisteredV1) &&
               registration.name == command.name && registration.scope == command.scope &&
               skill_stream?(event, registration.skill_id) && event.stream_revision.zero?
          raise InvalidProjectionSource, "Skill publication registration does not match its natural key"
        end

        registration
      end

      def load_payload(event)
        @schema_registry.load(
          type: event.type, schema_version: event.metadata.fetch("schema_version"), data: event.data
        )
      end

      def skill_stream?(event, skill_id)
        event.stream.context == "AgentKnowledge" && event.stream.stream_name == "Skill" &&
          event.stream.stream_id == skill_id
      end
    end
  end
end
