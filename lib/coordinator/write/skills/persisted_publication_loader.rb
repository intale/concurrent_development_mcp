# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class PersistedPublicationLoader
      include Dry::Monads[:result]

      CURRENT_SCHEMA_VERSION = 2
      PRE_SEMANTIC_SCHEMA_VERSION = 1

      def initialize(
        schema_registry: EventSchemaRegistry.new,
        pre_semantic_contract: Contracts::PreSemanticSkillRevision.new,
        identity_builder: IdentityBuilder.new,
        revision_builder: RevisionBuilder.new
      )
        @schema_registry = schema_registry
        @pre_semantic_contract = pre_semantic_contract
        @identity_builder = identity_builder
        @revision_builder = revision_builder
      end

      def call(event)
        schema_version = event.metadata["schema_version"]
        return load_current(event) if schema_version == CURRENT_SCHEMA_VERSION
        return load_pre_semantic(event) if schema_version == PRE_SEMANTIC_SCHEMA_VERSION

        Failure(invalid_event(schema_version:, errors: { schema_version: [ "is unsupported" ] }))
      end

      private

      def load_current(event)
        Success(
          @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          )
        )
      rescue EventSchemaRegistry::UnknownSchema, EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError, ArgumentError => error
        Failure(invalid_event(schema_version: event.metadata["schema_version"], errors: { payload: [ error.message ] }))
      end

      def load_pre_semantic(event)
        validation = @pre_semantic_contract.call(event.data)
        unless validation.success?
          return Failure(
            invalid_event(
              schema_version: PRE_SEMANTIC_SCHEMA_VERSION,
              errors: validation.errors.to_h
            )
          )
        end

        attributes = validation.to_h
        identity = @identity_builder.call(name: attributes.fetch(:name), scope: attributes.fetch(:scope))
        unless identity.skill_id == attributes.fetch(:skill_id)
          return Failure(
            invalid_event(
              schema_version: PRE_SEMANTIC_SCHEMA_VERSION,
              errors: { skill_id: [ "does not match the persisted name and scope" ] }
            )
          )
        end

        content_result = @revision_builder.call(
          identity:,
          description: attributes.fetch(:description),
          instructions: attributes.fetch(:instructions),
          assets: attributes.fetch(:assets).map { normalize_asset(_1) }
        )
        return content_result if content_result.failure?

        content = content_result.value!
        Success(
          Events::SkillRevisionPublishedV2.new(
            skill_id: identity.skill_id,
            name: identity.name,
            scope: identity.scope,
            revision: attributes.fetch(:revision),
            description: content.description,
            instructions: content.instructions,
            assets: content.assets,
            content_digest: content.content_digest,
            published_at: attributes.fetch(:published_at)
          )
        )
      end

      def normalize_asset(asset)
        base64 = asset.fetch(:content_base64)
        bytes = base64.unpack1("m0")
        text = bytes.dup.force_encoding(Encoding::UTF_8)
        content =
          if text.valid_encoding?
            { encoding: "utf-8", media_type: asset.fetch(:media_type), text: }
          else
            { encoding: "binary", media_type: asset.fetch(:media_type), base64: }
          end

        {
          path: asset.fetch(:path),
          executable: asset.fetch(:executable),
          content:
        }
      end

      def invalid_event(schema_version:, errors:)
        OutcomeError.new(
          code: :stored_skill_revision_invalid,
          message: "Persisted Skill revision is invalid",
          details: { schema_version:, errors: }
        )
      end
    end
  end
end
