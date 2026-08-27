# frozen_string_literal: true

RSpec.describe Coordinator::Write::Tasks::ExecutionLane do
  subject(:execution_lane) { described_class.new }

  it "routes one command identity deterministically to one of two versioned lanes" do
    command_id = "cmd-task-lane-deterministic"

    expect(execution_lane.index(command_id)).to eq(execution_lane.index(command_id))
    expect(execution_lane.index(command_id)).to be_between(0, described_class::COUNT - 1)
    expect(execution_lane.marker(command_id)).to eq(
      execution_lane.marker_for(execution_lane.index(command_id))
    )
  end

  it "publishes distinct exact markers for every configured lane" do
    expect(described_class::COUNT.times.map { execution_lane.marker_for(_1) }).to eq(
      [ "task-execution-lane:v1:0", "task-execution-lane:v1:1" ]
    )
  end
end
