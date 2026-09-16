# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DecisionHeadReferenceResolver
      include Dry::Monads[:result]

      TARGETS = {
        "DecisionActivated" => [ "DecisionActivated", "activate-decision" ],
        "DecisionDefinitionCorrected" => [ "DecisionDefinitionCorrected", "correct-decision-definition" ]
      }.freeze

      def initialize(target_event_reference_resolver:)
        @target_event_reference_resolver = target_event_reference_resolver
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        head:
      )
        reference = head.event
        target = TARGETS[reference.type]
        return Failure(inconsistent(source_event, "unsupported head event type")) unless target
        unless head.decision_id == reference.stream_id && head.decision_revision == reference.stream_revision
          return Failure(inconsistent(source_event, "head does not match its event reference"))
        end

        resolved = @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: reference,
          target_stream_context: "HumanGuidance",
          target_stream_name: "Decision",
          identity_role: "decision",
          target_event_type: target.fetch(0),
          target_step_name: target.fetch(1)
        )
        return resolved if resolved.failure?

        target_reference = resolved.value!
        Success(
          Decisions::DecisionHeadV1.new(
            decision_id: target_reference.stream_id,
            decision_revision: target_reference.stream_revision,
            event: target_reference
          )
        )
      end

      private

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Decision head reference is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
