# frozen_string_literal: true

RSpec.describe Coordinator::Write::Tasks::ExecutionLane do
  subject(:execution_lane) { described_class.new }

  it "routes one Task UUID deterministically from its random bits" do
    task_id = "018f0c00-0000-7000-8000-000000000007"

    expect(execution_lane.index(task_id)).to eq(execution_lane.index(task_id))
    expect(execution_lane.index(task_id)).to be_between(0, described_class::COUNT - 1)
    expect(execution_lane.marker(task_id)).to eq(
      execution_lane.marker_for(execution_lane.index(task_id))
    )
  end

  it "publishes distinct exact markers for every configured lane" do
    expect(described_class::COUNT.times.map { execution_lane.marker_for(_1) }).to eq(
      [ "task-execution-lane:v2:0", "task-execution-lane:v2:1" ]
    )
  end
end
