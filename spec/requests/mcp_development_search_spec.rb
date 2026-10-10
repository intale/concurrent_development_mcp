# frozen_string_literal: true

RSpec.describe "MCP development_search", :read_model do
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap { _1.host! "localhost" }
  end

  def rpc(method, params, status: 200)
    session.post("/mcp", params: JSON.generate(jsonrpc: "2.0", id: "search-request", method:, params: params.merge(_meta: {
      "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities" => { extensions: { "io.modelcontextprotocol/tasks" => {} } },
      "io.modelcontextprotocol/clientInfo" => { name: "search-spec", version: "1" }
    })), headers: {
      "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
      "MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => method, "Mcp-Name" => params[:name]
    }.compact)
    expect(session.response.status).to eq(status), session.response.body
    JSON.parse(session.response.body)
  end

  def literal(value = "checkpoint", **attributes)
    { match: "contains", value:, **attributes }
  end

  def arguments(**options)
    { fields: [ { field: "skill.instructions", query: literal } ], **options }
  end

  def call_search(input = arguments)
    rpc("tools/call", { name: "development_search", arguments: input }).fetch("result")
  end

  it "advertises strict bounded literal/Boolean inputs and typed read-only output without Task execution" do
    listed = rpc("tools/list", {}).dig("result", "tools")
    tool = listed.find { _1.fetch("name") == "development_search" }
    expect(tool).not_to be_nil
    expect(tool.fetch("annotations")).to include("readOnlyHint" => true, "idempotentHint" => true, "openWorldHint" => false)
    schema = JSONSchemer.schema(tool.fetch("inputSchema"))
    nested = arguments(fields: [ { field: "skill.instructions", query: { operator: "or", operands: [ literal("foo"),
      { operator: "and", operands: [ literal("bar", match: "starts_with"), literal("baz", match: "ends_with", case_sensitive: false) ] }
    ] } } ])
    expect(schema.valid?(JSON.parse(JSON.generate(nested)))).to be(true)
    [ arguments(regex: "foo"), arguments(limit: 51), arguments(combine: "and"),
      arguments(fields: [ { field: "skills.arbitrary_column", query: literal } ]),
      arguments(fields: [ { field: "skill.instructions", query: literal("xy") } ]) ].each do |invalid|
      expect(schema.valid?(JSON.parse(JSON.generate(invalid)))).to be(false)
    end
    expect(JSON.generate(tool.fetch("outputSchema"))).to include("retrieval_actions", "skill_get", "observation_id")
    instructions = rpc("server/discover", {}).dig("result", "instructions")
    expect(instructions).to include("development_search", "one raw scalar", "positive", "live keyset", "three consecutive")
  end

  it "returns a bounded available page and a schema-valid canonical retrieval action" do
    skill = create(:coordinator_read_skill, scope: "project:search")
    create(:coordinator_read_skill_revision, skill:, instructions: "Use checkpoint context.")
    response = call_search(arguments(filters: { scope: skill.scope }))
    expect(response).not_to have_key("taskId")
    payload = response.fetch("structuredContent")
    expect(payload).to include("status" => "ok", "command_id" => nil, "receipt" => nil)
    item = payload.dig("data", "page", "items").sole
    action = item.fetch("retrieval_actions").sole
    expect(action).to include("tool" => "skill_get", "arguments" => include("revision" => 1))
    retrieved = rpc("tools/call", { name: action.fetch("tool"), arguments: action.fetch("arguments") })
    expect(retrieved.dig("result", "structuredContent", "data", "skill", "instructions")).to eq("Use checkpoint context.")
    tools = rpc("tools/list", {}).dig("result", "tools")
    schema = tools.find { _1.fetch("name") == "development_search" }.fetch("outputSchema")
    expect(JSONSchemer.schema(schema).valid?(payload)).to be(true)
  end

  it "reports unanchored alternatives and query-mismatched cursors as structured invalid results" do
    invalid = call_search(arguments(fields: [ { field: "skill.instructions", query: { operator: "or", operands: [
      literal("foo"), { operator: "not", operands: [ literal("bar") ] }
    ] } } ]))
    expect(invalid.dig("structuredContent", "status")).to eq("invalid")
    expect(invalid.dig("structuredContent", "data", "code")).to eq("invalid_input")
    2.times do
      skill = create(:coordinator_read_skill)
      create(:coordinator_read_skill_revision, skill:, instructions: "checkpoint")
    end
    cursor = call_search(arguments(limit: 1)).dig("structuredContent", "data", "page", "cursor")
    mismatch = call_search(arguments(cursor:, filters: { scope: "project:other" }))
    expect(mismatch.dig("structuredContent", "data", "code")).to eq("invalid_cursor")
  end

  it "bounds both MCP text and structured output rather than silently dropping large hits" do
    text = "needle " + "界" * 233
    create_list(:coordinator_read_development_artifact, 35, title: text, content_text: text,
      source_locator: text, source_revision: text, source_collector: text, labels: [ "needle " + "界" * 121 ])
    input = { fields: %w[title content source_locator source_revision source_collector labels].map do |field|
      { field: "development_artifact.#{field}", query: literal("needle") }
    end, limit: 35 }
    query = Coordinator::Container["search.query_builder"].call(input).value!
    expect(Coordinator::Container["repositories.development_search"].page(query)).to be_success
    response = call_search(input)
    expect(response.dig("structuredContent", "status")).to eq("limit_reached")
    expect(response.dig("structuredContent", "data", "code")).to eq("search_response_limit")
    expect(response.dig("structuredContent", "data")).not_to have_key("page")
    expect(JSON.generate(response).bytesize).to be <= Coordinator::Read::Search::Limits::RESPONSE_BYTES
    expect(call_search(input.merge(limit: 5)).dig("structuredContent", "data", "page", "items").length).to eq(5)
  end
end
