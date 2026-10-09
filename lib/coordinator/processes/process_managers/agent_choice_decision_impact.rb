# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class AgentChoiceDecisionImpact
      HANDLED_START_CODES = [ :agent_choice_impact_scan_already_decided ].freeze
      HANDLED_PROGRESS_CODES = [
        :agent_choice_impact_scan_not_running,
        :agent_choice_impact_scan_checkpoint_changed,
        :stale_stream
      ].freeze

      def initialize(
        event_store:,
        source_builder: AgentChoiceImpacts::SourceBuilder.new(event_store:),
        checkpoint_loader: AgentChoiceImpacts::ScanCheckpointLoader.new(event_store:),
        page_reader: AgentChoiceImpacts::PageReader.new(event_store:),
        repair_planner: AgentChoiceImpacts::RepairPlanner.new(event_store:),
        command_builder: AgentChoiceImpacts::CommandBuilder.new(event_store:),
        start_scan: Coordinator::Write::Operations::ExecuteStartAgentChoiceImpactScan.new(event_store:),
        progress_scan: Coordinator::Write::Operations::ExecuteProgressAgentChoiceImpactScan.new(event_store:),
        assess_impact: Coordinator::Write::Operations::ExecuteAssessAgentChoiceDecisionImpact.new(event_store:)
      )
        @source_builder = source_builder
        @checkpoint_loader = checkpoint_loader
        @page_reader = page_reader
        @repair_planner = repair_planner
        @command_builder = command_builder
        @start_scan = start_scan
        @progress_scan = progress_scan
        @assess_impact = assess_impact
      end

      def call(event)
        source = @source_builder.call(event)
        case source.payload
        when Coordinator::Write::Events::DecisionActivatedV2,
             Coordinator::Write::Events::DecisionDefinitionCorrectedV2
          start_scan(source)
        when Coordinator::Write::Events::AgentChoiceImpactScanStartedV2,
             Coordinator::Write::Events::AgentChoiceImpactScanProgressedV2
          process_page(source)
        when Coordinator::Write::Events::AgentChoiceAcceptedV2
          repair_choice(source)
        end
        nil
      end

      private

      def start_scan(source)
        execute!(
          @start_scan.call(@command_builder.start(source)),
          handled_codes: HANDLED_START_CODES,
          transition: "start"
        )
      end

      def process_page(source)
        checkpoint = @checkpoint_loader.call(source)
        return unless checkpoint

        page = @page_reader.call(checkpoint)
        page.accepted_choices.each do |accepted_choice|
          execute!(
            @assess_impact.call(
              @command_builder.assess(
                accepted_choice:,
                decision_change: checkpoint.decision_change,
                caused_by: checkpoint.event
              )
            ),
            handled_codes: [],
            transition: "assess page target"
          )
        end
        execute!(
          @progress_scan.call(@command_builder.progress(checkpoint:, page:)),
          handled_codes: HANDLED_PROGRESS_CODES,
          transition: "progress"
        )
      end

      def repair_choice(source)
        plan = @repair_planner.call(source)
        plan.targets.each do |target|
          execute!(
            @assess_impact.call(
              @command_builder.assess(
                accepted_choice: plan.accepted_choice,
                decision_change: target.decision_change,
                caused_by: plan.accepted_choice
              )
            ),
            handled_codes: [],
            transition: "repair"
          )
        end
      end

      def execute!(result, handled_codes:, transition:)
        return result.value! if result.success?
        return if handled_codes.include?(result.failure.code)

        failure = result.failure
        raise AgentChoiceImpactProcessRejected,
              "AgentChoice impact #{transition} rejected: #{failure.code} - #{failure.message}"
      end
    end
  end
end
