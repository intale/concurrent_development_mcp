# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyCommandRejectionBuilder
      include Dry::Monads[:result]

      def initialize(entity_reference_resolver:, target_event_reference_resolver:, schema_registry: EventSchemaRegistry.new)
        @entity_reference_resolver = entity_reference_resolver
        @target_event_reference_resolver = target_event_reference_resolver
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
        elsif document.fetch(:code) == "candidate_head_already_registered"
          details = document.fetch(:details).to_h.transform_keys(&:to_sym)
          reference = @target_event_reference_resolver.call(
            migration_id:, source_config_name:, source_upper_position:, source_event:,
            source_reference: EventReference.new(details.fetch(:existing_event).to_h.transform_keys(&:to_sym)),
            target_stream_context: "DevelopmentIntegration", target_stream_name: "CandidateHead",
            identity_role: "candidate-head", target_event_type: "CandidateHeadRegistered",
            target_step_name: "register-candidate-head"
          )
          return reference if reference.failure?

          repository = @entity_reference_resolver.call(
            migration_id:, source_config_name:, source_upper_position:, source_event:,
            source_stream: StreamReference.new(context: "DevelopmentPlanning", stream_name: "Repository", stream_id: details.fetch(:repository_id)),
            target_stream_context: "DevelopmentPlanning", target_stream_name: "Repository", identity_role: "repository"
          )
          return repository if repository.failure?

          document = document.merge(details: details.merge(
            existing_event: reference.value!.to_h, repository_id: repository.value!.target_stream.stream_id
          ))
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
