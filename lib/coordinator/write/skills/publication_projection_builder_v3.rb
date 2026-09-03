# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class PublicationProjectionBuilderV3
      include Dry::Monads[:result]

      REVISION_EVENT_TYPES = %w[
        SkillRevisionCreated
        SkillRevisionDescriptionDefined
        SkillRevisionInstructionsDefined
        SkillAssetAddedToRevision
      ].freeze
      ASSET_EVENT_TYPES = %w[
        SkillAssetCreated
        SkillAssetPathDefined
        SkillAssetContentDefined
        SkillAssetExecutabilityDefined
      ].freeze

      def initialize(event_store:, schema_registry: EventSchemaRegistry.new, stream_factory: StreamFactory.new)
        @event_store = event_store
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def call(publication_event)
        publication = load_event(publication_event)
        registration = load_registration(publication.skill_id)
        revision_events = load_revision(publication.skill_revision_id)
        created = revision_events.fetch(Events::SkillRevisionCreatedV1)
        verify_revision!(publication, created)
        assets = revision_events.fetch(Events::SkillAssetAddedToRevisionV1, []).map do |assignment|
          verify_assignment!(publication, assignment)
          load_asset(assignment.asset_id)
        end

        Success(
          ProjectionPublicationV3.new(
            skill_id: publication.skill_id,
            skill_revision_id: publication.skill_revision_id,
            name: registration.name,
            scope: registration.scope,
            revision: publication.revision,
            description: revision_events.fetch(Events::SkillRevisionDescriptionDefinedV1).description,
            instructions: revision_events.fetch(Events::SkillRevisionInstructionsDefinedV1).instructions,
            assets:,
            content_digest: publication_event.metadata.fetch("content_digest"),
            published_at: publication_event.created_at.utc.iso8601(6)
          )
        )
      rescue EventSchemaRegistry::UnknownSchema, EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError, ArgumentError => error
        Failure(
          OutcomeError.new(
            code: :stored_skill_revision_invalid,
            message: "Persisted granular Skill revision is invalid",
            details: { errors: { payload: [ error.message ] } }
          )
        )
      end

      private

      def load_registration(skill_id)
        event = @event_store.read(
          @stream_factory.skill(skill_id),
          EventReadCriteria.new(event_types: [ "SkillRegistered" ], maximum_count: 1, direction: :asc)
        ).first
        raise KeyError, "Skill registration is missing" unless event

        load_event(event)
      end

      def load_revision(skill_revision_id)
        events = @event_store.read(
          @stream_factory.skill_revision(skill_revision_id),
          EventReadCriteria.new(
            event_types: REVISION_EVENT_TYPES,
            maximum_count: 3 + Types::SKILL_ASSET_MAXIMUM_COUNT,
            direction: :asc
          )
        )
        group_unique(events.map { load_event(_1) })
      end

      def load_asset(asset_id)
        envelopes = @event_store.read(
          @stream_factory.skill_asset(asset_id),
          EventReadCriteria.new(event_types: ASSET_EVENT_TYPES, maximum_count: 4, direction: :asc)
        )
        events = group_unique(envelopes.map { load_event(_1) })
        created = events.fetch(Events::SkillAssetCreatedV1)
        raise ArgumentError, "Skill asset identity does not match its stream" unless created.asset_id == asset_id

        content_event = envelopes.find { _1.type == "SkillAssetContentDefined" }
        raise KeyError, "Skill asset content fact is missing" unless content_event
        content = events.fetch(Events::SkillAssetContentDefinedV1)
        metadata = content_event.metadata
        content_value = if metadata.fetch("encoding") == "utf-8"
                          Content::TextV1.new(
                            encoding: "utf-8",
                            media_type: metadata.fetch("media_type"),
                            text: content.content,
                            content_sha256: metadata.fetch("content_sha256"),
                            byte_size: metadata.fetch("byte_size")
                          )
                        else
                          Content::BinaryV1.new(
                            encoding: "binary",
                            media_type: metadata.fetch("media_type"),
                            base64: content.content,
                            content_sha256: metadata.fetch("content_sha256"),
                            byte_size: metadata.fetch("byte_size")
                          )
                        end
        AssetV2.new(
          path: events.fetch(Events::SkillAssetPathDefinedV1).path,
          executable: events.fetch(Events::SkillAssetExecutabilityDefinedV1).executable,
          content: content_value
        )
      end

      def group_unique(events)
        grouped = events.group_by(&:class)
        grouped.each do |type, values|
          next if type == Events::SkillAssetAddedToRevisionV1
          raise ArgumentError, "Expected one #{type.name} fact" unless values.one?
        end
        grouped.transform_values do |values|
          type = values.first.class
          type == Events::SkillAssetAddedToRevisionV1 ? values : values.first
        end
      end

      def verify_revision!(publication, created)
        return if created.skill_revision_id == publication.skill_revision_id &&
                  created.skill_id == publication.skill_id && created.revision == publication.revision

        raise ArgumentError, "Skill revision identity does not match its publication"
      end

      def verify_assignment!(publication, assignment)
        return if assignment.skill_revision_id == publication.skill_revision_id &&
                  assignment.skill_id == publication.skill_id && assignment.revision == publication.revision

        raise ArgumentError, "Skill asset assignment does not match its publication"
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
