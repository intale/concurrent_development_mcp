# frozen_string_literal: true

RSpec.describe Coordinator::Mcp::UsageSkills::Catalog do
  def usage_call(name, arguments = {})
    response = JSON.parse(Coordinator::Container["mcp.server"].handle_json(JSON.generate(
      jsonrpc: "2.0", id: 1, method: "tools/call", params: { name:, arguments: }
    )))
    expect(response).not_to have_key("error")
    expect(response.dig("result", "isError")).not_to be(true)
    response.fetch("result").fetch("structuredContent")
  end

  it "documents every public function exactly once in selectable capability guides" do
    covered = described_class.all.flat_map(&:tools)
    expect(covered).to contain_exactly(*Coordinator::Mcp::ToolRegistry.all.map(&:tool_name))
    expect(covered.uniq).to eq(covered)
    described_class.all.each do |definition|
      definition.tools.each { expect(definition.instructions).to include("| #{_1} |") }
    end
  end

  it "serves the complete static catalog and guide bodies without any read-database queries" do
    statements = []
    recorder = ->(*event) { statements << event.last.fetch(:sql) }
    ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") do
      page = usage_call("skill_list").dig("data", "page")
      expect(page.fetch("items").map { _1.fetch("name") }).to eq(described_class.all.map(&:name).sort)
      expect(page.fetch("has_more")).to be(false)
      page.fetch("items").each do |item|
        expect(item).to include("source" => "server", "scope" => described_class::SCOPE, "revision" => described_class::RELEASE)
        expect(item).not_to have_key("published")
        document = usage_call("skill_get", name: item.fetch("name"), scope: item.fetch("scope")).dig("data", "skill")
        definition = described_class.all.find { _1.name == item.fetch("name") }
        expect(document).to include("instructions" => definition.instructions, "tools" => definition.tools, "assets" => [])
        expect(document).not_to have_key("published")
      end
    end
    expect(statements).to be_empty
  end

  it "pages deterministically and applies an exact built-in name filter" do
    names = []
    cursor = nil
    loop do
      page = usage_call("skill_list", scope: described_class::SCOPE, after_skill_id: cursor, limit: 2).dig("data", "page")
      names.concat(page.fetch("items").map { _1.fetch("name") })
      break unless page.fetch("has_more")

      cursor = page.fetch("next_skill_id")
    end
    expect(names).to eq(described_class.all.map(&:name).sort)
    filtered = usage_call("skill_list", name: described_class::ENTRY_SKILL, source: "server").dig("data", "page", "items")
    expect(filtered.map { _1.fetch("name") }).to eq([ described_class::ENTRY_SKILL ])
  end

  it "returns static not-found and invalid-cursor outcomes without consulting projections" do
    statements = []
    recorder = ->(*event) { statements << event.last.fetch(:sql) }
    ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") do
      [
        { name: "unknown-server-guide", scope: described_class::SCOPE },
        { name: described_class::ENTRY_SKILL, scope: described_class::SCOPE, revision: described_class::RELEASE + 1 }
      ].each do |input|
        result = usage_call("skill_get", input)
        expect(result).to include("status" => "not_found")
        expect(result.dig("data", "code")).to eq("server_skill_not_found")
      end
      asset = usage_call("skill_asset_get", name: described_class::ENTRY_SKILL, scope: described_class::SCOPE, path: "absent.md")
      expect(asset.dig("data", "code")).to eq("server_skill_asset_not_found")
      invalid = usage_call("skill_list", after_skill_id: "unknown-server-guide")
      expect(invalid.fetch("status")).to eq("invalid")
    end
    expect(statements).to be_empty
  end
end

RSpec.describe "Stored Skills remain separate from built-in usage guides", :read_model do
  def stored_skill_call(name, arguments)
    JSON.parse(Coordinator::Container["mcp.server"].handle_json(JSON.generate(
      jsonrpc: "2.0", id: 1, method: "tools/call", params: { name:, arguments: }
    ))).dig("result", "structuredContent")
  end

  it "retrieves a project entity sharing a built-in name through its exact project scope" do
    catalog = Coordinator::Mcp::UsageSkills::Catalog
    skill = create(:coordinator_read_skill, name: catalog::ENTRY_SKILL, scope: "project:example")
    create(:coordinator_read_skill_revision, skill:, instructions: "Project-owned instructions.")
    project = stored_skill_call("skill_get", name: skill.name, scope: skill.scope).dig("data", "skill")
    expect(project.fetch("instructions")).to eq("Project-owned instructions.")
    expect(project).to have_key("published")
    built_in = stored_skill_call("skill_get", name: skill.name, scope: catalog::SCOPE).dig("data", "skill")
    expect(built_in.fetch("source")).to eq("server")
    expect(built_in.fetch("instructions")).not_to eq(project.fetch("instructions"))
  end

  it "discovers stored entities by project scope or explicitly across scopes" do
    %w[home work].each do |scope|
      skill = create(:coordinator_read_skill, name: "review", scope:)
      create(:coordinator_read_skill_revision, skill:)
    end
    scoped = stored_skill_call("skill_list", scope: "home", name: "review").dig("data", "page", "items")
    expect(scoped.map { _1.fetch("scope") }).to eq([ "home" ])
    all = stored_skill_call("skill_list", source: "stored", name: "review").dig("data", "page", "items")
    expect(all.map { _1.fetch("scope") }).to contain_exactly("home", "work")
  end
end
