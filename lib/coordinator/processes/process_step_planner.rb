# frozen_string_literal: true

module Coordinator::Processes
  class ProcessStepPlanner
    def initialize(event_store:, planner: Coordinator::Write::ProcessSteps::Planner.new(event_store:))
      @planner = planner
    end

    def call(source_event:, process_name:, step_name:, subject_kind:, subject_id:, rule_version:, allocate_target_entity:)
      result = @planner.call(
        source_event:,
        process_name:,
        step_name:,
        subject_kind:,
        subject_id:,
        rule_version:,
        allocate_target_entity:
      )
      return result.value! if result.success?

      failure = result.failure
      raise ProcessStepPlanningRejected,
            "#{process_name}/#{step_name} could not be planned: #{failure.code} - #{failure.message}"
    end
  end
end
