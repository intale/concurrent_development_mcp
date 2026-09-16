# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class AgentChoiceImpactV1Transformer
      include Dry::Monads[:result]

      ASSESSMENT_STEP = "record-agent-choice-impact-assessment"
      ACCEPTED_SOURCE_STEP = "link-agent-choice-impact-accepted-choice"
      DECISION_SOURCE_STEP = "link-agent-choice-impact-decision-change"
      INVALIDATION_STEP = "invalidate-agent-choice-by-decision"

      def initialize(
        event_store:,
        context_resolver:,
        target_event_reference_resolver:,
        marker_builder: AgentChoiceImpacts::AssessmentMarkerBuilder.new,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @context_resolver = context_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @marker_builder = marker_builder
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        case source_payload
        when Events::AgentChoiceImpactAssessedV1
          transform_assessment(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::AgentChoiceInvalidatedByDecisionV1
          transform_invalidation(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        end
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def transform_assessment(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        context = resolve_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          assessment_event: source_event,
          assessment: source
        )
        return context if context.failure?

        value = context.value!
        common_markers = assessment_markers(value)
        expanded_markers = invalidation_markers(value)
        Success([
          fact(
            value.assessment_stream,
            Events::AgentChoiceImpactAssessmentRecordedV1.new(
              assessment_id: value.assessment_id,
              choice_id: value.choice_id,
              attempt_id: value.attempt_id,
              assessment: value.assessment
            ),
            common_markers,
            ASSESSMENT_STEP,
            actor_metadata(
              source_event,
              policy_version: value.policy_version,
              before_context_digest: value.before_context.digest,
              after_context_digest: value.after_context.digest
            )
          ),
          fact(
            value.assessment_stream,
            Events::AgentChoiceImpactSourceLinkedV1.new(
              assessment_id: value.assessment_id,
              role: "accepted_choice",
              source: value.accepted_choice
            ),
            expanded_markers,
            ACCEPTED_SOURCE_STEP,
            actor_metadata(source_event, policy_version: value.policy_version)
          ),
          fact(
            value.assessment_stream,
            Events::AgentChoiceImpactSourceLinkedV1.new(
              assessment_id: value.assessment_id,
              role: "decision_change",
              source: value.decision_change
            ),
            expanded_markers,
            DECISION_SOURCE_STEP,
            actor_metadata(source_event, policy_version: value.policy_version)
          )
        ])
      end

      def transform_invalidation(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        assessment_event = exact_event(source.assessment_event, source_upper_position:)
        assessment = assessment_event && load(assessment_event)
        unless assessment.is_a?(Events::AgentChoiceImpactAssessedV1)
          return Failure(inconsistent(source_event, "referenced assessment is absent"))
        end

        context = resolve_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          assessment_event:,
          assessment:
        )
        return context if context.failure?

        value = context.value!
        assessment_reference = @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: source.assessment_event,
          target_stream: value.assessment_stream,
          target_event_type: "AgentChoiceImpactAssessmentRecorded",
          target_step_name: ASSESSMENT_STEP
        )
        return assessment_reference if assessment_reference.failure?

        valid_invalidation!(
          source_event:,
          source:,
          assessment:,
          context: value,
          assessment_reference: assessment_reference.value!
        )
        Success([
          fact(
            value.choice_stream,
            Events::AgentChoiceInvalidatedByDecisionV2.new(
              choice_id: value.choice_id,
              reason: source.reason
            ),
            invalidation_markers(value),
            INVALIDATION_STEP,
            actor_metadata(
              source_event,
              policy_version: value.policy_version,
              previous_context_digest: value.before_context.digest,
              resulting_context_digest: value.after_context.digest
            )
          )
        ])
      end

      def resolve_context(**arguments)
        @context_resolver.call(**arguments)
      end

      def valid_invalidation!(source_event:, source:, assessment:, context:, assessment_reference:)
        valid = source_event.stream.context == "AgentGovernance" &&
                source_event.stream.stream_name == "AgentChoice" &&
                source_event.stream.stream_id == source.choice_id &&
                source_event.stream_revision == 2 &&
                source_event.metadata.fetch("policy_version") == context.policy_version &&
                source_event.metadata.fetch("actor_kind") == "system" &&
                source_event.metadata.fetch("actor_id") == "agent-choice-decision-impact" &&
                source.choice_id == assessment.choice_id &&
                source.accepted_choice == assessment.accepted_choice &&
                source.decision_change_event == assessment.decision_change.source_event &&
                source.previous_context_digest == assessment.assessment.before_context_digest &&
                source.resulting_context_digest == assessment.assessment.after_context_digest &&
                source.reason == assessment.assessment.reason &&
                assessment.assessment.outcome == "invalidated" &&
                assessment_reference.stream_revision.zero? &&
                assessment_reference.stream_id == context.assessment_id &&
                context.accepted_choice.stream_id == context.choice_id
        raise ArgumentError, "Choice invalidation does not match its assessment" unless valid
      end

      def assessment_markers(context)
        [
          "impact-assessment:#{context.assessment_id}",
          "choice:#{context.choice_id}",
          "attempt:#{context.attempt_id}",
          "decision:#{context.decision_change.stream_id}",
          "decision-change:#{context.decision_change.event_id}",
          @marker_builder.call(
            accepted_choice: context.accepted_choice,
            decision_change: context.decision_change
          )
        ].freeze
      end

      def invalidation_markers(context)
        query = context.before_context.document.query_context
        markers = assessment_markers(context) + [
          "choice-type:#{context.choice_type}",
          "work-item:#{query.work_item_id}",
          "change-set:#{query.change_set_id}",
          "repository:#{query.repository_id}"
        ]
        markers.concat(
          context.before_context.document.partitions.map do |observation|
            "decision-partition:#{observation.partition.partition_id}"
          end
        ).uniq.freeze
      end

      def actor_metadata(source_event, **attributes)
        MigrationMetadataExtensionV1.new(
          attributed_actor: Commands::Actor.new(
            kind: source_event.metadata.fetch("actor_kind"),
            id: source_event.metadata.fetch("actor_id")
          ),
          **attributes
        )
      end

      def fact(target_stream, event, markers, step_name, metadata_extension)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension:
        )
      end

      def exact_event(reference, source_upper_position:)
        event = @event_store.read_at(
          StreamReference.new(
            context: reference.stream_context,
            stream_name: reference.stream_name,
            stream_id: reference.stream_id
          ),
          reference.stream_revision
        )
        return unless event && event.id == reference.event_id && event.type == reference.type
        return unless event.global_position <= source_upper_position

        event
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "AgentChoice impact lifecycle source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
