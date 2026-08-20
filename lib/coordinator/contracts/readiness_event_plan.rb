# frozen_string_literal: true

module Coordinator
  module Contracts
    class ReadinessEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:expected_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :expected_stream) do
        plan = values[:plan]
        expected_stream = values[:expected_stream]
        write = plan.writes.first

        unless plan.writes.one? && write.stream == expected_stream && write.event.class == Events::WorkItemMadeReadyV1
          key(:plan).failure("must contain one WorkItemMadeReady write to the target WorkItem stream")
        end
      end
    end
  end
end
