# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Interpretations
      class Propose
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new,
          topic_registry: Coordinator::Write::Interpretations::TopicRegistry.new,
          topic_value_contract: Contracts::InterpretationTopicValue.new,
          topic_policy_contract: Contracts::CandidateImpactPolicyProposal.new,
          source_contract: Contracts::InterpretationSourceEvidence.new,
          scope_resolver: ScopeResolver.new,
          assessment: ProposalAssessment.new
        )
          @stream_factory = stream_factory
          @topic_registry = topic_registry
          @topic_value_contract = topic_value_contract
          @topic_policy_contract = topic_policy_contract
          @source_contract = source_contract
          @scope_resolver = scope_resolver
          @assessment = assessment
        end

        def call(state:, command:, proposed_at:)
          return duplicate_failure(command.interpretation_id) if state.proposal_exists
          return missing_source_failure(command.source_message_id) unless state.source

          source_validation = validate_source(command, state.source)
          return source_validation if source_validation.failure?

          definition = @topic_registry.fetch(command.proposed_decision.topic_id)
          return unsupported_topic_failure(command.proposed_decision.topic_id) unless definition

          topic_validation = validate_topic_value(command, definition)
          return topic_validation if topic_validation.failure?

          resolution = @scope_resolver.call(
            submitted_scope: command.proposed_decision.scope,
            source: state.source
          )
          assessment = @assessment.call(
            command:,
            scope: resolution.scope,
            provenance: resolution.provenance
          )
          proposal = build_proposal(
            command:,
            source: state.source,
            scope: resolution.scope,
            provenance: resolution.provenance,
            assessment:,
            proposed_at:
          )

          Success(build_plan(command.interpretation_id, proposal, assessment))
        end

        private

        def validate_source(command, source)
          result = @source_contract.call(
            source_message_id: command.source_message_id,
            persisted_message_id: source.message_id,
            source_text: source.text,
            source_span: command.source_span&.to_h
          )
          return Success() if result.success?

          Failure(
            OutcomeError.new(
              code: :source_span_mismatch,
              message: "Source span does not match persisted guidance",
              details: {
                message_id: command.source_message_id,
                interpretation_id: command.interpretation_id
              }
            )
          )
        end

        def validate_topic_value(command, definition)
          result = @topic_value_contract.call(
            expected_schema: definition.value_schema,
            value_schema: command.proposed_decision.value.schema
          )
          if result.success?
            result = @topic_policy_contract.call(decision: command.proposed_decision)
            return Success() if result.success?
          end

          Failure(
            OutcomeError.new(
              code: :topic_value_invalid,
              message: "Decision value does not match the topic registry",
              details: {
                topic_id: command.proposed_decision.topic_id,
                expected_schema: definition.value_schema,
                supplied_schema: command.proposed_decision.value.schema
              }
            )
          )
        end

        def build_proposal(command:, source:, scope:, provenance:, assessment:, proposed_at:)
          submitted = command.proposed_decision
          Events::DecisionInterpretationProposedV2.new(
            interpretation_id: command.interpretation_id,
            source_message_id: command.source_message_id,
            source_span: command.source_span&.text || source.text,
            proposed_decision: Coordinator::Write::Interpretations::ProposedDecisionV1.new(
              submitted.to_h.merge(scope:)
            ),
            ambiguities: command.ambiguities.map(&:description),
            assessment: assessment.status
          )
        end

        def build_plan(interpretation_id, proposal, assessment)
          stream = @stream_factory.interpretation(interpretation_id)
          events = [ proposal ]
          unless assessment.status == "accepted_for_activation"
            events << Events::DecisionClarificationRequiredV2.new(
              interpretation_id: proposal.interpretation_id,
              source_message_id: proposal.source_message_id,
              origin: "proposal_assessment",
              reasons: assessment.reasons,
              questions: assessment.questions.map(&:prompt),
              rationale: assessment.reasons.join(", ")
            )
          end

          EventPlan.new(
            writes: events.map { EventWrite.new(stream:, event: _1) }
          )
        end

        def duplicate_failure(interpretation_id)
          Failure(
            OutcomeError.new(
              code: :interpretation_already_proposed,
              message: "Interpretation ID is already proposed",
              details: { interpretation_id: }
            )
          )
        end

        def missing_source_failure(message_id)
          Failure(
            OutcomeError.new(
              code: :guidance_message_not_found,
              message: "Source guidance message does not exist",
              details: { message_id: }
            )
          )
        end

        def unsupported_topic_failure(topic_id)
          Failure(
            OutcomeError.new(
              code: :topic_not_supported,
              message: "Topic is not present in the executable registry",
              details: { topic_id: }
            )
          )
        end
      end
    end
  end
end
