# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyCommandRejectionBuilder
      include Dry::Monads[:result]

      def initialize(entity_reference_resolver:, schema_registry: EventSchemaRegistry.new)
        @entity_reference_resolver = entity_reference_resolver
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, command_id:, error:, retryable:)
        document = error.to_h.transform_keys(&:to_sym)
        if %w[skill_identity_conflict skill_revision_conflict].include?(document.fetch(:code))
          details = document.fetch(:details).to_h.transform_keys(&:to_sym)
          skill = @entity_reference_resolver.call(
            migration_id:, source_config_name:, source_upper_position:, source_event:,
            source_stream: StreamReference.new(context: "AgentKnowledge", stream_name: "Skill", stream_id: details.fetch(:skill_id)),
            target_stream_context: "AgentKnowledge", target_stream_name: "Skill", identity_role: "skill"
          )
          return skill if skill.failure?

          document = document.merge(details: details.merge(skill_id: skill.value!.target_stream.stream_id))
        end

        Success(@schema_registry.load(
          type: "CommandRejected", schema_version: 2,
          data: { command_id:, error: document, retryable: }
        ))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(TransformationErrorV1.new(
          code: :invalid_source_event,
          message: "Historical rejection cannot satisfy current typed evidence: #{error.message[0, 1000]}",
          event_type: source_event.type, schema_version: source_event.metadata["schema_version"], source_event_id: source_event.id
        ))
      end
    end
  end
end
