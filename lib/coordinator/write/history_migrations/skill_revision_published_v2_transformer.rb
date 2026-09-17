# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class SkillRevisionPublishedV2Transformer
      include Dry::Monads[:result]

      MARKER_CODEC_VERSION = "compound-marker-v2"

      def initialize(
        event_store:,
        stream_identity_allocator:,
        schema_registry: LegacyEventSchemaRegistry.new,
        marker_builder: Skills::MarkerBuilder.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @schema_registry = schema_registry
        @marker_builder = marker_builder
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        validate_source!(source_event, source_payload, source_upper_position:)
        context = allocate_context(
          migration_id:,
          source_config_name:,
          source_event:,
          asset_count: source_payload.assets.length
        )
        return context if context.failure?

        Success(transformed_facts(context.value!, source_event, source_payload).freeze)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error,
             EventHistoryLimitExceeded, EventSchemaRegistry::UnknownSchema,
             EventSchemaRegistry::SchemaMismatch => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def allocate_context(migration_id:, source_config_name:, source_event:, asset_count:)
        skill = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_name: "Skill",
          identity_role: "skill"
        )
        return skill if skill.failure?

        revision = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_name: "SkillRevision",
          identity_role: "skill-revision-#{source_event.stream_revision}"
        )
        return revision if revision.failure?

        asset_streams = []
        asset_count.times do |index|
          asset = allocate(
            migration_id:,
            source_config_name:,
            source_event:,
            target_stream_name: "SkillAsset",
            identity_role: format("skill-asset-%<revision>d-%<index>04d", revision: source_event.stream_revision, index:)
          )
          return asset if asset.failure?

          asset_streams << asset.value!.target_stream
        end

        Success(
          SkillRevisionMigrationContextV1.new(
            skill_stream: skill.value!.target_stream,
            revision_stream: revision.value!.target_stream,
            asset_streams:
          )
        )
      end

      def allocate(
        migration_id:,
        source_config_name:,
        source_event:,
        target_stream_name:,
        identity_role:
      )
        @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "AgentKnowledge",
          target_stream_name:,
          identity_role:
        )
      end

      def transformed_facts(context, source_event, source)
        facts = []
        facts << registration_fact(context, source_event, source) if source.revision == 1
        facts.concat(revision_facts(context, source_event, source))
        source.assets.each_with_index do |asset, index|
          facts.concat(asset_facts(context, source_event, source, asset, index:))
        end
        facts << publication_fact(context, source_event, source)
        facts
      end

      def registration_fact(context, source_event, source)
        fact(
          target_stream: context.skill_stream,
          event: Events::SkillRegisteredV1.new(
            skill_id: context.skill_id,
            name: source.name,
            scope: source.scope
          ),
          markers: skill_markers(context) + [ @marker_builder.natural_key(name: source.name, scope: source.scope) ],
          step_name: "register-skill",
          metadata_extension: metadata(
            source_event,
            marker_codec_version: MARKER_CODEC_VERSION
          )
        )
      end

      def revision_facts(context, source_event, source)
        markers = revision_markers(context)
        [
          fact(
            target_stream: context.revision_stream,
            event: Events::SkillRevisionCreatedV1.new(
              skill_revision_id: context.skill_revision_id,
              skill_id: context.skill_id,
              revision: source.revision
            ),
            markers:,
            step_name: "create-skill-revision",
            metadata_extension: metadata(source_event)
          ),
          fact(
            target_stream: context.revision_stream,
            event: Events::SkillRevisionDescriptionDefinedV1.new(
              skill_revision_id: context.skill_revision_id,
              description: source.description
            ),
            markers:,
            step_name: "define-skill-revision-description",
            metadata_extension: metadata(source_event)
          ),
          fact(
            target_stream: context.revision_stream,
            event: Events::SkillRevisionInstructionsDefinedV1.new(
              skill_revision_id: context.skill_revision_id,
              instructions: source.instructions
            ),
            markers:,
            step_name: "define-skill-revision-instructions",
            metadata_extension: text_metadata(
              source_event,
              source.instructions,
              media_type: "text/markdown"
            )
          )
        ]
      end

      def asset_facts(context, source_event, source, asset, index:)
        target_stream = context.asset_streams.fetch(index)
        asset_id = target_stream.stream_id
        suffix = format("%04d", index)
        markers = asset_markers(context, asset_id)
        [
          fact(
            target_stream:,
            event: Events::SkillAssetCreatedV1.new(asset_id:),
            markers:,
            step_name: "create-skill-asset-#{suffix}",
            metadata_extension: metadata(source_event)
          ),
          fact(
            target_stream:,
            event: Events::SkillAssetPathDefinedV1.new(asset_id:, path: asset.path),
            markers:,
            step_name: "define-skill-asset-path-#{suffix}",
            metadata_extension: metadata(source_event)
          ),
          fact(
            target_stream:,
            event: Events::SkillAssetContentDefinedV1.new(
              asset_id:,
              content: content_representation(asset.content)
            ),
            markers:,
            step_name: "define-skill-asset-content-#{suffix}",
            metadata_extension: content_metadata(source_event, asset.content)
          ),
          fact(
            target_stream:,
            event: Events::SkillAssetExecutabilityDefinedV1.new(
              asset_id:,
              executable: asset.executable
            ),
            markers:,
            step_name: "define-skill-asset-executability-#{suffix}",
            metadata_extension: metadata(source_event)
          ),
          fact(
            target_stream: context.revision_stream,
            event: Events::SkillAssetAddedToRevisionV1.new(
              skill_revision_id: context.skill_revision_id,
              skill_id: context.skill_id,
              revision: source.revision,
              asset_id:
            ),
            markers: revision_markers(context),
            step_name: "add-skill-asset-to-revision-#{suffix}",
            metadata_extension: metadata(source_event)
          )
        ]
      end

      def publication_fact(context, source_event, source)
        fact(
          target_stream: context.skill_stream,
          event: Events::SkillRevisionPublishedV3.new(
            skill_id: context.skill_id,
            skill_revision_id: context.skill_revision_id,
            revision: source.revision
          ),
          markers: revision_markers(context),
          step_name: "publish-skill-revision",
          metadata_extension: metadata(source_event, content_digest: source.content_digest)
        )
      end

      def fact(target_stream:, event:, markers:, step_name:, metadata_extension:)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension:
        )
      end

      def skill_markers(context)
        [ "skill:#{context.skill_id}" ]
      end

      def revision_markers(context)
        skill_markers(context) + [ "skill-revision:#{context.skill_revision_id}" ]
      end

      def asset_markers(context, asset_id)
        skill_markers(context) + [ "skill-asset:#{asset_id}" ]
      end

      def text_metadata(source_event, text, media_type:)
        bytes = text.b
        metadata(
          source_event,
          encoding: "utf-8",
          media_type:,
          byte_size: bytes.bytesize,
          content_sha256: "sha256:#{OpenSSL::Digest::SHA256.hexdigest(bytes)}"
        )
      end

      def content_metadata(source_event, content)
        metadata(
          source_event,
          encoding: content.encoding,
          media_type: content.media_type,
          byte_size: content.byte_size,
          content_sha256: content.content_sha256
        )
      end

      def metadata(source_event, **attributes)
        MigrationMetadataExtensionV1.new(
          attributed_actor: actor_from(source_event),
          policy_version: source_event.metadata.fetch("policy_version"),
          **attributes
        )
      end

      def actor_from(source_event)
        Commands::Actor.new(
          kind: source_event.metadata.fetch("actor_kind"),
          id: source_event.metadata.fetch("actor_id")
        )
      end

      def content_representation(content)
        content.respond_to?(:text) ? content.text : content.base64
      end

      def validate_source!(source_event, source, source_upper_position:)
        stream = stream_for(source_event)
        valid = source.is_a?(Events::SkillRevisionPublishedV2) &&
                source_event.type == "SkillRevisionPublished" &&
                source_event.metadata.fetch("schema_version") == 2 &&
                source_event.global_position <= source_upper_position &&
                stream.context == "AgentKnowledge" &&
                stream.stream_name == "Skill" &&
                stream.stream_id == source.skill_id &&
                source_event.stream_revision == source.revision - 1 &&
                source_event.markers.include?("skill:#{source.skill_id}")
        raise ArgumentError, "source identity, schema, stream, revision, or markers are invalid" unless valid

        validate_root!(source_event, source, source_upper_position:)
      end

      def validate_root!(source_event, source, source_upper_position:)
        root = @event_store.read_at(stream_for(source_event), 0)
        root_payload = root && load(root)
        valid = root &&
                root.global_position <= source_upper_position &&
                root_payload.is_a?(Events::SkillRevisionPublishedV2) &&
                root_payload.skill_id == source.skill_id &&
                root_payload.name == source.name &&
                root_payload.scope == source.scope &&
                root_payload.revision == 1 &&
                root.markers.include?("skill:#{source.skill_id}")
        raise ArgumentError, "source Skill root is absent or inconsistent" unless valid
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def stream_for(event)
        StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Skill revision source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
