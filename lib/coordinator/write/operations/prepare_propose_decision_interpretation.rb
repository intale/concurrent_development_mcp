# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareProposeDecisionInterpretation < Dry::Operation
      def initialize(
        contract: Contracts::ProposeDecisionInterpretation.new,
        topic_policy_contract: Contracts::CandidateImpactPolicyProposal.new
      )
        @contract = contract
        @topic_policy_contract = topic_policy_contract
      end

      def call(input)
        attributes = step validate(input)

        command = step build_command(attributes)

        step validate_topic_policy(command)
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "ProposeDecisionInterpretation input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_command(attributes)
        actor = attributes.fetch(:actor)
        Success(
          Commands::ProposeDecisionInterpretation.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            interpretation_id: attributes.fetch(:interpretation_id),
            source_message_id: attributes.fetch(:source_message_id),
            source_span: build_source_span(attributes.fetch(:source_span)),
            classifier: build_classifier(attributes.fetch(:classifier)),
            proposed_decision: build_proposed_decision(attributes.fetch(:proposed_decision)),
            ambiguities: attributes.fetch(:ambiguities).map { build_ambiguity(_1) }
          )
        )
      end

      def validate_topic_policy(command)
        result = @topic_policy_contract.call(decision: command.proposed_decision)
        return Success(command) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "ProposeDecisionInterpretation topic policy is invalid",
            details: { proposed_decision: result.errors.to_h.fetch(:decision) }
          )
        )
      end

      def build_source_span(attributes)
        return unless attributes

        Interpretations::SourceSpanV1.new(attributes)
      end

      def build_classifier(attributes)
        Interpretations::ClassifierAttributionV1.new(
          id: attributes.fetch(:id),
          version: attributes.fetch(:version),
          ontology_version: attributes.fetch(:ontology_version),
          confidence_millionths: attributes.fetch(:confidence_millionths)
        )
      end

      def build_proposed_decision(attributes)
        Interpretations::SubmittedDecisionV1.new(
          statement_kind: attributes.fetch(:statement_kind),
          topic_id: attributes.fetch(:topic_id),
          effect: attributes.fetch(:effect),
          modality: attributes.fetch(:modality),
          value: build_value(attributes.fetch(:value)),
          scope: build_scope(attributes.fetch(:scope)),
          conditions: build_conditions(attributes.fetch(:conditions)),
          validity: build_validity(attributes.fetch(:validity)),
          authority: Interpretations::DecisionAuthorityV1.new(attributes.fetch(:authority)),
          enforcement: Interpretations::DecisionEnforcementV1.new(attributes.fetch(:enforcement)),
          relations: build_relations(attributes.fetch(:relations))
        )
      end

      def build_value(attributes)
        Interpretations::DecisionValueV1.new(
          schema: attributes.fetch(:schema),
          name: attributes.fetch(:name),
          items: attributes.fetch(:items)&.sort,
          target_kind: attributes.fetch(:target_kind),
          target_id: attributes.fetch(:target_id),
          action: attributes.fetch(:action)
        )
      end

      def build_scope(attributes)
        return unless attributes

        Interpretations::DecisionScopeV1.new(
          workspace_id: attributes.fetch(:workspace_id),
          repository_ids: attributes.fetch(:repository_ids).sort,
          branch_selectors: attributes.fetch(:branch_selectors).sort,
          change_set_id: attributes.fetch(:change_set_id),
          work_item_id: attributes.fetch(:work_item_id),
          attempt_id: attributes.fetch(:attempt_id),
          candidate_id: attributes.fetch(:candidate_id),
          path_selectors: attributes.fetch(:path_selectors).sort,
          symbol_selectors: attributes.fetch(:symbol_selectors).sort,
          contract_selectors: attributes.fetch(:contract_selectors).sort,
          schema_selectors: attributes.fetch(:schema_selectors).sort,
          environments: attributes.fetch(:environments).sort,
          agent_roles: attributes.fetch(:agent_roles).sort
        )
      end

      def build_conditions(attributes)
        Interpretations::DecisionConditionsV1.new(
          phases: attributes.fetch(:phases).sort,
          languages: attributes.fetch(:languages).sort,
          tags: attributes.fetch(:tags).sort,
          repository_kinds: attributes.fetch(:repository_kinds).sort,
          artifact_kinds: attributes.fetch(:artifact_kinds).sort,
          environments: attributes.fetch(:environments).sort
        )
      end

      def build_validity(attributes)
        until_event = attributes.fetch(:until_event)
        Interpretations::DecisionValidityV1.new(
          valid_from: attributes.fetch(:valid_from),
          valid_until: attributes.fetch(:valid_until),
          until_event: until_event && Interpretations::UntilEventConditionV1.new(until_event)
        )
      end

      def build_relations(attributes)
        Interpretations::DecisionRelationsV1.new(
          corrects: attributes.fetch(:corrects).sort,
          supersedes: attributes.fetch(:supersedes).sort,
          exception_to: attributes.fetch(:exception_to).sort,
          revokes: attributes.fetch(:revokes).sort
        )
      end

      def build_ambiguity(attributes)
        Interpretations::InterpretationAmbiguityV1.new(
          field: attributes.fetch(:field),
          code: attributes.fetch(:code),
          description: attributes.fetch(:description),
          options: attributes.fetch(:options)
        )
      end
    end
  end
end
