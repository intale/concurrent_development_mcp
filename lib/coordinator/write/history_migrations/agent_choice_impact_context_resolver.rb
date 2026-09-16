# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class AgentChoiceImpactContextResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        target_event_reference_resolver:,
        head_reference_resolver:,
        document_transformer:,
        source_builder: AgentChoiceImpacts::DecisionChangeEvidenceBuilder.new(event_store:),
        reconstructor: AgentChoiceImpacts::HistoricalContextReconstructor.new(event_store:),
        assessment_contract: Contracts::AgentChoiceImpactAssessment.new,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @target_event_reference_resolver = target_event_reference_resolver
        @head_reference_resolver = head_reference_resolver
        @document_transformer = document_transformer
        @source_builder = source_builder
        @reconstructor = reconstructor
        @assessment_contract = assessment_contract
        @schema_registry = schema_registry
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        assessment_event:,
        assessment:
      )
        valid_assessment_envelope!(assessment_event, assessment, source_upper_position:)
        recorded_event, recorded = load_recorded_choice(
          assessment_event:,
          assessment:,
          source_upper_position:
        )
        accepted_choice = resolve_accepted_choice(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: assessment.accepted_choice
        )
        return accepted_choice if accepted_choice.failure?

        decision_change = authoritative_decision_change(
          source_event:,
          assessment_event:,
          assessment:,
          source_upper_position:
        )
        return decision_change if decision_change.failure?

        target_change = resolve_decision_change(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          decision_change: decision_change.value!
        )
        return target_change if target_change.failure?

        reconstruction = @reconstructor.call(
          recorded_choice: recorded,
          decision_change: decision_change.value!
        )
        valid_assessment!(
          assessment_event:,
          assessment:,
          recorded_event:,
          recorded:,
          reconstruction:
        )
        contexts = transform_contexts(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          reconstruction:
        )
        return contexts if contexts.failure?

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: assessment_event,
          target_stream_context: "AgentGovernance",
          target_stream_name: "AgentChoiceImpact",
          identity_role: "agent-choice-impact-assessment"
        )
        return allocation if allocation.failure?

        before_context, after_context = contexts.value!
        accepted_reference = accepted_choice.value!
        choice_stream = StreamReference.new(
          context: accepted_reference.stream_context,
          stream_name: accepted_reference.stream_name,
          stream_id: accepted_reference.stream_id
        )
        Success(
          AgentChoiceImpactContextV1.new(
            assessment_stream: allocation.value!.target_stream,
            choice_stream:,
            assessment_id: allocation.value!.target_stream.stream_id,
            choice_id: accepted_reference.stream_id,
            attempt_id: before_context.document.query_context.attempt_id,
            choice_type: recorded.choice_type,
            accepted_choice: accepted_reference,
            decision_change: target_change.value!.event,
            before_context:,
            after_context:,
            assessment: AgentChoiceImpacts::ImpactAssessmentV2.new(
              before_evaluation: assessment.assessment.before_evaluation,
              after_evaluation: assessment.assessment.after_evaluation,
              outcome: assessment.assessment.outcome,
              reason: assessment.assessment.reason
            ),
            policy_version: assessment.assessment.policy_version
          )
        )
      rescue AgentChoiceImpacts::InvalidHistory => error
        Failure(inconsistent(source_event, "#{error.reason}: #{error.evidence.inspect}"))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def valid_assessment_envelope!(event, assessment, source_upper_position:)
        valid = event.global_position <= source_upper_position &&
                event.type == "AgentChoiceImpactAssessed" &&
                event.metadata.fetch("schema_version") == 1 &&
                event.stream.context == "AgentGovernance" &&
                event.stream.stream_name == "AgentChoiceImpact" &&
                event.stream.stream_id == assessment.assessment_id &&
                event.stream_revision.zero? &&
                event.metadata.fetch("actor_kind") == "system" &&
                event.metadata.fetch("actor_id") == "agent-choice-decision-impact"
        raise ArgumentError, "impact assessment identity does not match its source stream" unless valid
      end

      def load_recorded_choice(assessment_event:, assessment:, source_upper_position:)
        accepted_event = exact_event(assessment.accepted_choice, source_upper_position:)
        accepted = accepted_event && load(accepted_event)
        unless accepted.is_a?(Events::AgentChoiceAcceptedV1) &&
            accepted.choice_id == assessment.choice_id &&
            accepted.context_digest &&
            accepted_event.global_position < assessment_event.global_position
          raise ArgumentError, "accepted Choice reference is inconsistent"
        end

        recorded_event = exact_event(accepted.recorded_event, source_upper_position:)
        recorded = recorded_event && load(recorded_event)
        valid = recorded.is_a?(Events::AgentChoiceRecordedV1) &&
                recorded.choice_id == assessment.choice_id &&
                recorded.context.attempt_id == assessment.attempt_id &&
                recorded.decision_context.digest == accepted.context_digest &&
                same_stream?(accepted_event, recorded_event) &&
                recorded_event.stream_revision.zero? &&
                accepted_event.stream_revision == 1 &&
                recorded_event.global_position < accepted_event.global_position
        raise ArgumentError, "recorded Choice reference is inconsistent" unless valid

        [ recorded_event, recorded ]
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        raise ArgumentError, "AgentChoice source is invalid: #{error.message}"
      end

      def resolve_accepted_choice(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:
      )
        resolved = @target_event_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream_context: "AgentGovernance",
          target_stream_name: "AgentChoice",
          identity_role: "agent-choice",
          target_event_type: "AgentChoiceAccepted",
          target_step_name: "accept-agent-choice"
        )
        return resolved if resolved.failure?

        reference = resolved.value!
        valid = reference.stream_context == "AgentGovernance" &&
                reference.stream_name == "AgentChoice" &&
                reference.stream_revision == 1
        return resolved if valid

        Failure(inconsistent(source_event, "target accepted Choice reference is inconsistent"))
      end

      def authoritative_decision_change(source_event:, assessment_event:, assessment:, source_upper_position:)
        persisted = exact_event(assessment.decision_change.source_event, source_upper_position:)
        unless persisted && persisted.global_position < assessment_event.global_position
          return Failure(inconsistent(source_event, "decision change source is absent"))
        end

        built = @source_builder.call(persisted)
        unless built.success? && decision_change_attributes(assessment.decision_change) == built.value!.to_h
          return Failure(inconsistent(source_event, "embedded decision change is not authoritative"))
        end

        Success(built.value!)
      end

      def resolve_decision_change(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        decision_change:
      )
        @head_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          head: Decisions::DecisionHeadV1.new(
            decision_id: decision_change.decision_id,
            decision_revision: decision_change.source_event.stream_revision,
            event: decision_change.source_event
          )
        )
      end

      def valid_assessment!(assessment_event:, assessment:, recorded_event:, recorded:, reconstruction:)
        validation = @assessment_contract.call(assessment: assessment.assessment)
        valid = validation.success? &&
                assessment_event.metadata.fetch("policy_version") == assessment.assessment.policy_version &&
                assessment.accepted_choice.stream_id == recorded.choice_id &&
                recorded_event.stream.stream_id == recorded.choice_id &&
                assessment.assessment.before_context_digest == reconstruction.before_context.digest &&
                assessment.assessment.after_context_digest == reconstruction.after_context.digest &&
                assessment.assessment.before_evaluation == reconstruction.before_evaluation &&
                assessment.assessment.after_evaluation == reconstruction.after_evaluation &&
                assessment.assessment.source_advancements == reconstruction.source_advancements
        return if valid

        details = validation.failure? ? validation.errors.to_h.inspect : "semantic evidence differs"
        raise ArgumentError, "impact assessment is inconsistent: #{details}"
      end

      def transform_contexts(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        reconstruction:
      )
        common = {
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        }
        before_context = @document_transformer.decision_context(
          **common,
          context: reconstruction.before_context
        )
        return before_context if before_context.failure?

        after_context = @document_transformer.decision_context(
          **common,
          context: reconstruction.after_context
        )
        return after_context if after_context.failure?
        unless before_context.value!.document.query_context == after_context.value!.document.query_context
          return Failure(inconsistent(source_event, "before and after query contexts differ"))
        end

        Success([ before_context.value!, after_context.value! ])
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

      def decision_change_attributes(value)
        value.to_h.except(:changed_at)
      end

      def same_stream?(left, right)
        left.stream.context == right.stream.context &&
          left.stream.stream_name == right.stream.stream_name &&
          left.stream.stream_id == right.stream.stream_id
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "AgentChoice impact source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
