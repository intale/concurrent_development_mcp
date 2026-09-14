# frozen_string_literal: true

module Coordinator::Write::ProcessSteps
  class DispatchState < Coordinator::Write::Value
    attribute :planned, Coordinator::Write::Types.Instance(Coordinator::Write::Events::ProcessStepPlannedV1)
    attribute :failure,
              Coordinator::Write::Types.Instance(
                Coordinator::Write::Events::ProcessStepDispatchFailedV1
              ).optional

    def self.reduce(events)
      planned = events.first
      unless planned.is_a?(Coordinator::Write::Events::ProcessStepPlannedV1)
        raise Coordinator::Write::InvalidProcessStepPlan, "Process step history must start with ProcessStepPlanned"
      end
      if events.length > 2 || (events[1] && !events[1].is_a?(Coordinator::Write::Events::ProcessStepDispatchFailedV1))
        raise Coordinator::Write::InvalidProcessStepPlan, "Process step history has unsupported facts"
      end

      new(planned:, failure: events[1])
    end
  end
end
