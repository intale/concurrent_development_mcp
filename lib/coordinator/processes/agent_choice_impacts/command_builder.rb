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
        process_step_planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:),
        reference_builder: EventReferenceBuilder.new
      )
        @decision_change_builder = decision_change_builder
        @process_step_planner = process_step_planner
        @reference_builder = reference_builder
      end

      def start(source)
        decision_change = decision_change!(source.event)
        process_step = plan(
          source_event: source.event,
          step_name: "start-impact-scan",
          subject_kind: "decision-change",
          subject_id: decision_change.source_event.event_id,
          allocate_target_entity: true
        )
        command = Coordinator::Write::Commands::StartAgentChoiceImpactScan.new(
          command_id: process_step.target_command_id,
          actor: ACTOR,
          scan_id: process_step.target_entity_id!,
          source_event: decision_change.source_event,
          source_global_position: decision_change.source_global_position,
          policy_version: POLICY_VERSION
        )
        Coordinator::Write::AgentChoiceImpactScanInvocation.new(
          command:,
          source_event: source.event,
          source_reference: source.reference,
          caused_by: process_step.event
        )
      end

      def assess(accepted_choice:, decision_change:, caused_by:)
        accepted_reference = @reference_builder.call(accepted_choice)
        process_step = plan(
          source_event: caused_by,
          step_name: "assess-choice-impact",
          subject_kind: "choice-decision-change",
          subject_id: "#{accepted_reference.event_id}:#{decision_change.source_event.event_id}",
          allocate_target_entity: true
        )
        command = Coordinator::Write::Commands::AssessAgentChoiceDecisionImpact.new(
          command_id: process_step.target_command_id,
          actor: ACTOR,
          assessment_id: process_step.target_entity_id!,
          choice_id: accepted_reference.stream_id,
          accepted_choice: accepted_reference,
          decision_change:,
          policy_version: POLICY_VERSION
        )
        Coordinator::Write::AgentChoiceImpactAssessmentInvocation.new(
          command:,
          caused_by: process_step.event,
          caused_by_reference: process_step.reference
        )
      end

      def progress(checkpoint:, page:)
        process_step = plan(
          source_event: checkpoint.event,
          step_name: "progress-impact-scan",
          subject_kind: "impact-scan",
          subject_id: checkpoint.scan_id,
          allocate_target_entity: false
        )
        command = Coordinator::Write::Commands::ProgressAgentChoiceImpactScan.new(
          command_id: process_step.target_command_id,
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
          checkpoint_reference: checkpoint.reference,
          caused_by: process_step.event
        )
      end

      private

      def decision_change!(event)
        result = @decision_change_builder.call(event)
        return result.value! if result.success?

        raise AgentChoiceImpactProcessRejected,
              "Decision change cannot start impact processing: #{result.failure.details.inspect}"
      end

      def plan(source_event:, step_name:, subject_kind:, subject_id:, allocate_target_entity:)
        @process_step_planner.call(
          source_event:,
          process_name: "agent-choice-decision-impact",
          step_name:,
          subject_kind:,
          subject_id:,
          rule_version: POLICY_VERSION,
          allocate_target_entity:
        )
      end
    end
  end
end
