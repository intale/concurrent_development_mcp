# frozen_string_literal: true

RSpec.describe Coordinator::Write::StreamFactory do
  subject(:factory) { described_class.new }

  it "centralizes all first-slice stream identities" do
    expect(factory.command("cmd-1").to_h).to eq(
      context: "CoordinatorControl", stream_name: "Command", stream_id: "cmd-1"
    )
    expect(factory.change_set("CS-1").to_h).to eq(
      context: "DevelopmentPlanning", stream_name: "ChangeSet", stream_id: "CS-1"
    )
    expect(factory.work_item("W-1").to_h).to eq(
      context: "DevelopmentExecution", stream_name: "WorkItem", stream_id: "W-1"
    )
    expect(factory.attempt("A-1").to_h).to eq(
      context: "DevelopmentExecution", stream_name: "Attempt", stream_id: "A-1"
    )
  end
end
