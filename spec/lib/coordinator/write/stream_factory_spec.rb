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
    expect(factory.skill_revision("revision-1").to_h).to eq(
      context: "AgentKnowledge", stream_name: "SkillRevision", stream_id: "revision-1"
    )
    expect(factory.skill_asset("asset-1").to_h).to eq(
      context: "AgentKnowledge", stream_name: "SkillAsset", stream_id: "asset-1"
    )
    expect(factory.development_artifact_relation("relation-1").to_h).to eq(
      context: "DevelopmentMemory", stream_name: "DevelopmentArtifactRelation", stream_id: "relation-1"
    )
  end
end
