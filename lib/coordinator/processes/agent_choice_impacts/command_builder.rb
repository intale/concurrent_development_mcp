# frozen_string_literal: true

module Coordinator::Processes
  module AgentChoiceImpacts
    class CommandBuilder
      POLICY_VERSION = "agent-choice-decision-impact/v1"
      ACTOR = Coordinator::Write::Commands::Actor.new(
        kind: "system",
        id: "agent-choice-decision-impact"
      )

      def initialize(
        event_store:,
        decision_change_builder: Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceBuilder.new(event_store:),
        scan_identity_builder: Coordinator::Write::AgentChoiceImpacts::ScanIdentityBuilder.new,
        assessment_identity_builder: Coordinator::Write::AgentChoiceImpacts::AssessmentIdentityBuilder.new,
        reference_builder: EventReferenceBuilder.new
      )
        @decision_change_builder = decision_change_builder
        @scan_identity_builder = scan_identity_builder
        @assessment_identity_builder = assessment_identity_builder
        @reference_builder = reference_builder
      end

      def start(source)
        decision_change = decision_change!(source.event)
        scan_id = @scan_identity_builder.start(
          source_event: decision_change.source_event,
          policy_version: POLICY_VERSION
        )
        command = Coordinator::Write::Commands::StartAgentChoiceImpactScan.new(
          command_id: scan_id,
          actor: ACTOR,
          scan_id:,
          source_event: decision_change.source_event,
          source_global_position: decision_change.source_global_position,
          policy_version: POLICY_VERSION
        )
        Coordinator::Write::AgentChoiceImpactScanInvocation.new(
          command:,
          source_event: source.event,
          source_reference: source.reference
        )
      end

      def assess(accepted_choice:, decision_change:, caused_by:)
        accepted_reference = @reference_builder.call(accepted_choice)
        assessment_id = @assessment_identity_builder.call(
          accepted_choice: accepted_reference,
          decision_change: decision_change.source_event,
          policy_version: POLICY_VERSION
        )
        command = Coordinator::Write::Commands::AssessAgentChoiceDecisionImpact.new(
          command_id: assessment_id,
          actor: ACTOR,
          assessment_id:,
          choice_id: accepted_reference.stream_id,
          accepted_choice: accepted_reference,
          decision_change:,
          policy_version: POLICY_VERSION
        )
        Coordinator::Write::AgentChoiceImpactAssessmentInvocation.new(
          command:,
          caused_by:,
          caused_by_reference: @reference_builder.call(caused_by)
        )
      end

      def progress(checkpoint:, page:)
        command_id = @scan_identity_builder.progress(
          checkpoint_event: checkpoint.reference,
          policy_version: POLICY_VERSION
        )
        command = Coordinator::Write::Commands::ProgressAgentChoiceImpactScan.new(
          command_id:,
          actor: ACTOR,
          scan_id: checkpoint.scan_id,
          expected_checkpoint: checkpoint.reference,
          previous_from_position: checkpoint.from_position,
          last_processed_position: page.last_processed_position,
          page_choice_count: page.accepted_choices.length,
          has_more: page.has_more,
          policy_version: POLICY_VERSION
        )
        Coordinator::Write::AgentChoiceImpactScanProgressInvocation.new(
          command:,
          checkpoint_event: checkpoint.event,
          checkpoint_reference: checkpoint.reference
        )
      end

      private

      def decision_change!(event)
        result = @decision_change_builder.call(event)
        return result.value! if result.success?

        raise AgentChoiceImpactProcessRejected,
              "Decision change cannot start impact processing: #{result.failure.details.inspect}"
      end
    end
  end
end
