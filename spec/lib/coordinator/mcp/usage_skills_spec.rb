# frozen_string_literal: true

RSpec.describe Coordinator::Mcp::UsageSkills::Catalog, :read_model do
  it "assigns every published tool to exactly one focused usage topic" do
    covered = described_class.all.flat_map(&:tools)
    expect(covered).to contain_exactly(*Coordinator::Mcp::ToolRegistry.all.map(&:tool_name))
    expect(covered.uniq).to eq(covered)
  end

  it "provides a unique entry and valid public name/scope tuples without publishing on discovery" do
    definitions = described_class.all
    expect(definitions.map(&:name).uniq.length).to eq(definitions.length)
    expect(definitions.count { _1.name == described_class::ENTRY_SKILL }).to eq(1)
    definitions.each do |definition|
      result = Coordinator::Read::Contracts::SkillGet.new.call(name: definition.name, scope: described_class::SCOPE)
      expect(result).to be_success
    end
  end

  it "serves the complete product snapshot through normal factory-backed Skill queries" do
    server = Coordinator::Container["mcp.server"]
    described_class.all.each_with_index do |definition, index|
      skill = create(:coordinator_read_skill, name: definition.name, scope: described_class::SCOPE)
      create(:coordinator_read_skill_revision, skill:, description: definition.description, instructions: definition.instructions)
      response = JSON.parse(server.handle_json(JSON.generate(
        jsonrpc: "2.0", id: index + 1, method: "tools/call",
        params: { name: "skill_get", arguments: { name: definition.name, scope: described_class::SCOPE } }
      )))
      expect(response.dig("result", "structuredContent", "data", "skill")).to include(
        "name" => definition.name, "scope" => described_class::SCOPE,
        "description" => definition.description, "instructions" => definition.instructions, "assets" => []
      )
    end
  end

  it "does not synthesize missing product Skills from the distribution catalog" do
    query = Coordinator::Container["queries.skill_get"]
    result = query.call(name: described_class::ENTRY_SKILL, scope: described_class::SCOPE)
    expect(result.value!.status).to eq("not_found")
  end
end
