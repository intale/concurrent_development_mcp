# frozen_string_literal: true

RSpec.describe "ART-01 MCP Development Artifacts" do
  ART_PROTOCOL_VERSION = "2026-07-28"
  ART_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "captures through a Task and records authoritative artifact facts", :event_store do
    task_id = call_tool("development_artifact_capture", capture_input, id: 1)
      .dig("result", "taskId")
    execute_task(task_id)
    outcome = task_request("tasks/get", task_id, id: 2)
      .dig("result", "result", "structuredContent")
    artifact_id = outcome.dig("data", "artifact_id")
    observation_id = outcome.dig("data", "observation_id")

    expect(outcome).to include(
      "status" => "ok",
      "data" => include(
        "outcome" => "captured",
        "artifact_id" => a_string_matching(Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ID_PATTERN),
        "observation_id" => a_string_matching(
          Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_OBSERVATION_ID_PATTERN
        ),
        "classification_revision" => 1
      )
    )
    expect(artifact_events(artifact_id).map(&:type)).to eq([ "DevelopmentArtifactCaptured" ])
    expect(observation_events(observation_id).map(&:type)).to eq([ "DevelopmentArtifactObserved" ])
  end

  it "serves projected metadata and passive content independently", :read_model do
    artifact = create(
      :coordinator_read_development_artifact,
      scope: "project:alpha",
      title: "MCP Artifact",
      labels: %w[docs mcp],
      content_text: "MCP artifact body\n",
      content_byte_size: 18,
      source_locator: "docs/mcp.md",
      source_revision: nil
    )
    observation = create(
      :coordinator_read_development_artifact_observation,
      artifact:,
      scope: artifact.scope,
      title: artifact.title,
      labels: artifact.labels,
      source_locator: artifact.source_locator,
      source_revision: nil
    )
    artifact_id = artifact.artifact_id
    observation_id = observation.observation_id

    metadata = call_tool("development_artifact_get", { artifact_id:, observation_id: }, id: 3)
      .dig("result", "structuredContent")
    content = call_tool("development_artifact_content_get", { artifact_id: }, id: 4)
      .dig("result", "structuredContent")
    resolved = call_tool(
      "development_artifact_locator_resolve",
      {
        scope: "project:alpha",
        source_kind: "local_file",
        locator: "docs/mcp.md",
        source_revision: nil
      },
      id: 5
    ).dig("result", "structuredContent")
    listed = call_tool(
      "development_artifact_list",
      { scope: "project:alpha", limit: 10 },
      id: 6
    ).dig("result", "structuredContent")
    expect(metadata.dig("data", "artifact", "artifact")).to include(
      "artifact_id" => artifact_id,
      "observation_id" => observation_id,
      "scope" => "project:alpha",
      "classification_revision" => 1,
      "classification_reason" => nil,
      "observed" => include("event" => include("type" => "DevelopmentArtifactObserved")),
      "classified" => include("event" => include("type" => "DevelopmentArtifactObserved"))
    )
    expect(metadata.to_s).not_to include("MCP artifact body")
    projected_content = content.dig("data", "content")
    expect(projected_content).to include(
      "encoding" => "utf-8",
      "text" => "MCP artifact body\n"
    )
    expect(projected_content).not_to have_key("base64")
    expect(content.fetch("warnings").sole).to include("passive data")
    expect(resolved.dig("data", "page")).to include(
      "resolution" => "unique",
      "items" => [ include("artifact_id" => artifact_id) ]
    )
    expect(resolved.fetch("next_actions").sole).to include(
      "tool" => "development_artifact_content_get",
      "arguments" => { "artifact_id" => artifact_id }
    )
    expect(listed.dig("data", "page", "items")).to include(
      include("artifact_id" => artifact_id)
    )
  end

  it "corrects one observation classification and rejects a stale revision through Tasks", :event_store do
    capture_task = call_tool(
      "development_artifact_capture",
      capture_input(command_id: "cmd-mcp-classification-capture"),
      id: 1
    ).dig("result", "taskId")
    execute_task(capture_task)
    captured = task_request("tasks/get", capture_task, id: 2)
      .dig("result", "result", "structuredContent", "data")
    artifact_id = captured.fetch("artifact_id")
    observation_id = captured.fetch("observation_id")

    correction_task = call_tool(
      "development_artifact_classification_correct",
      {
        command_id: "cmd-mcp-classification-correct",
        actor: { kind: "agent", id: "agent-mcp-artifact" },
        observation_id:,
        expected_revision: 1,
        title: "Corrected MCP Artifact",
        kind: "contract",
        labels: %w[corrected mcp],
        reason: "The captured bytes describe a requirement, not general documentation."
      },
      id: 3
    ).dig("result", "taskId")
    execute_task(correction_task)
    corrected = task_request("tasks/get", correction_task, id: 4)
      .dig("result", "result", "structuredContent")
    expect(corrected).to include(
      "status" => "ok",
      "data" => include(
        "artifact_id" => artifact_id,
        "observation_id" => observation_id,
        "classification_revision" => 2,
        "kind" => "contract",
        "outcome" => "corrected"
      )
    )

    stale_task = call_tool(
      "development_artifact_classification_correct",
      {
        command_id: "cmd-mcp-classification-stale",
        actor: { kind: "agent", id: "agent-mcp-artifact" },
        observation_id:,
        expected_revision: 1,
        title: "Stale correction",
        kind: "documentation",
        labels: [ "stale" ],
        reason: "This command was based on an obsolete projected classification."
      },
      id: 6
    ).dig("result", "taskId")
    execute_task(stale_task)
    stale = task_request("tasks/get", stale_task, id: 7)
      .dig("result", "result", "structuredContent")
    expect(stale.dig("data", "code")).to eq(
      "development_artifact_classification_revision_conflict"
    )
    expect(observation_events(observation_id).map(&:type)).to eq(
      [ "DevelopmentArtifactObserved", "DevelopmentArtifactClassificationCorrected" ]
    )
  end

  it "serves the latest projected observation classification", :read_model do
    artifact = create(:coordinator_read_development_artifact, scope: "project:alpha")
    classified_event = {
      "event_id" => SecureRandom.uuid_v7,
      "type" => "DevelopmentArtifactClassificationCorrected",
      "stream_context" => "DevelopmentMemory",
      "stream_name" => "DevelopmentArtifactObservation",
      "stream_id" => "artifact-observation:v1:#{'c' * 64}",
      "stream_revision" => 1
    }
    observation = create(
      :coordinator_read_development_artifact_observation,
      artifact:,
      observation_id: classified_event.fetch("stream_id"),
      scope: artifact.scope,
      title: "Corrected MCP Artifact",
      kind: "contract",
      labels: %w[corrected mcp],
      classification_revision: 2,
      classification_reason: "The captured bytes describe a requirement, not general documentation.",
      classified_event:,
      classified_global_position: 902,
      classified_at_domain: Time.utc(2026, 8, 30, 12, 2),
      classified_at_store: Time.utc(2026, 8, 30, 12, 2, 1)
    )

    exact = call_tool(
      "development_artifact_get",
      { artifact_id: artifact.artifact_id, observation_id: observation.observation_id },
      id: 5
    ).dig("result", "structuredContent", "data", "artifact", "artifact")

    expect(exact).to include(
      "observation_id" => observation.observation_id,
      "classification_revision" => 2,
      "classification_reason" => "The captured bytes describe a requirement, not general documentation.",
      "kind" => "contract",
      "classified" => include(
        "event" => include("type" => "DevelopmentArtifactClassificationCorrected")
      )
    )
  end

  it "teaches a clean client the complete two-pass linked-document workflow in tools/list" do
    response = mcp_request(id: 1, method: "tools/list", params: {}, name: "tools")
    tools = response.dig("result", "tools").index_by { _1.fetch("name") }
    capture = tools.fetch("development_artifact_capture")
    capture_batch = tools.fetch("development_artifact_capture_batch")
    classification = tools.fetch("development_artifact_classification_correct")
    declare = tools.fetch("development_artifact_relation_declare")
    declare_batch = tools.fetch("development_artifact_relation_declare_batch")
    traverse = tools.fetch("development_artifact_relation_list")
    resolve = tools.fetch("development_artifact_locator_resolve")

    expect(capture.fetch("description")).to include(
      "Import pass 1",
      "poll tasks/get",
      "result is unknown",
      "same command_id",
      "known terminal result",
      "new command_id"
    )
    expect(capture_batch.fetch("description")).to include(
      "1..1,000",
      "3-MiB",
      "operation_batch_get",
      "project path layout",
      "filesystem",
      "Git",
      "URL fetching"
    )
    expect(classification.fetch("description")).to include(
      "observation_id",
      "classification_revision",
      "stale expected revision",
      "provenance remain immutable"
    )
    expect(declare.fetch("description")).to include(
      "Import pass 2",
      "parent/index Artifact",
      "literal path",
      "fragment",
      "normalized_locator"
    )
    expect(declare_batch.fetch("description")).to include(
      "parse links client-side",
      "relative POSIX",
      "never guess unresolved or ambiguous targets",
      "import_manifest Artifact",
      "per-item Saga outcome"
    )
    expect(traverse.fetch("description")).to include(
      "outgoing from a parent/index",
      "incoming from a child",
      "peer summaries",
      "projection-observation continuation cursor"
    )
    expect(resolve.fetch("description")).to include(
      "splits its fragment",
      "POSIX semantics",
      "absent, unique, or ambiguous",
      "never",
      "latest",
      "projection lag"
    )

    relation_properties = declare.dig("inputSchema", "properties")
    expect(relation_properties.fetch("attributes").fetch("properties")).to include(
      "path",
      "fragment",
      "normalized_locator"
    )
    expect(relation_properties.fetch("supersedes").fetch("properties")).to include(
      "relation_id",
      "reason"
    )

    get_data = tools.fetch("development_artifact_get")
      .dig("outputSchema", "properties", "data", "oneOf", 0, "properties")
    get_input = tools.fetch("development_artifact_get").dig("inputSchema", "properties")
    artifact_summary = get_data.dig("artifact", "properties", "artifact", "properties")
    relation_page = traverse
      .dig("outputSchema", "properties", "data", "oneOf", 0, "properties", "page")
    locator_page = resolve
      .dig("outputSchema", "properties", "data", "oneOf", 0, "properties", "page")
    content = tools.fetch("development_artifact_content_get")
      .dig("outputSchema", "properties", "data", "oneOf", 0, "properties", "content")
    relation_item = relation_page.dig("properties", "items", "items", "properties")
    locator_actions = resolve
      .dig("outputSchema", "properties", "next_actions", "items", "oneOf")
    capture_data = capture
      .dig("outputSchema", "properties", "data", "oneOf", 0, "properties")
    classification_data = classification
      .dig("outputSchema", "properties", "data", "oneOf", 0, "properties")
    declare_data = declare
      .dig("outputSchema", "properties", "data", "oneOf", 0, "properties")
    expect(get_data).to include("artifact")
    expect(get_input).to include("artifact_id", "observation_id")
    expect(artifact_summary).to include(
      "observation_id",
      "classification_revision",
      "classification_reason",
      "relationship_capacity",
      "observed",
      "classified"
    )
    content_variants = content.fetch("oneOf").map { _1.fetch("properties") }
    expect(content_variants).to include(
      include("encoding", "media_type", "text", "content_sha256"),
      include("encoding", "media_type", "base64", "content_sha256")
    )
    expect(relation_page.fetch("properties")).to include(
      "artifact",
      "items",
      "continuation_cursor",
      "has_more"
    )
    expect(relation_item).to include(
      "direction",
      "display_relation",
      "inverse_relation",
      "transitive",
      "supersedable",
      "peer_id",
      "peer_artifact",
      "attributes",
      "declared",
      "superseded",
      "follow_action"
    )
    expect(
      locator_page.dig("properties", "resolution", "enum")
    ).to eq(%w[absent unique ambiguous])
    expect(locator_actions.map { _1.dig("properties", "tool", "const") }).to include(
      "development_artifact_content_get",
      "development_artifact_locator_resolve"
    )
    expect(capture_data).to include(
      "artifact_id",
      "observation_id",
      "classification_revision",
      "content_sha256",
      "outcome",
      "recorded_at"
    )
    expect(classification_data).to include(
      "artifact_id",
      "observation_id",
      "classification_revision",
      "title",
      "kind",
      "labels",
      "outcome",
      "corrected_at"
    )
    expect(declare_data).to include(
      "relation_id",
      "target",
      "superseded_relation_id",
      "outcome"
    )
  end

  it "runs capture and relation batches as idempotent Operation Batch Sagas", :event_store do
    batch_id = SecureRandom.uuid_v7
    created = call_tool(
      "development_artifact_capture_batch",
      {
        command_id: "cmd-artifact-capture-batch",
        actor: { kind: "agent", id: "agent-mcp-artifact" },
        batch_id:,
        items: [
          capture_input(command_id: "cmd-artifact-batch-1", locator: "one.md", text: "one\n"),
          capture_input(command_id: "cmd-artifact-batch-2", locator: "two.md", text: "two\n")
        ]
      },
      id: 1
    )
    execute_task(created.dig("result", "taskId"))
    run_batch(batch_id)
    artifact_ids = %w[cmd-artifact-batch-1 cmd-artifact-batch-2].map do |command_id|
      load_completion(command_id).data.artifact_id
    end

    relation_batch_id = SecureRandom.uuid_v7
    related = call_tool(
      "development_artifact_relation_declare_batch",
      {
        command_id: "cmd-artifact-relation-batch",
        actor: { kind: "agent", id: "agent-mcp-artifact" },
        batch_id: relation_batch_id,
        items: [
          {
            command_id: "cmd-artifact-batch-relation-1",
            actor: { kind: "agent", id: "agent-mcp-artifact" },
            source_artifact_id: artifact_ids.first,
            relation: "references",
            target: { kind: "artifact", id: artifact_ids.last },
            attributes: {
              path: "../two.md",
              fragment: "usage",
              normalized_locator: "two.md"
            }
          }
        ]
      },
      id: 2
    )
    execute_task(related.dig("result", "taskId"))
    run_batch(relation_batch_id)

    expect(load_completion("cmd-artifact-batch-relation-1").data).to have_attributes(
      source_artifact_id: artifact_ids.first,
      outcome: "declared"
    )
    expect(artifact_events(artifact_ids.first).map(&:type)).to eq(
      [ "DevelopmentArtifactCaptured", "DevelopmentArtifactRelationDeclared" ]
    )
    expect(artifact_events(artifact_ids.first).last.data.dig("artifact_relation", "attributes")).to include(
      "path" => "../two.md",
      "fragment" => "usage",
      "normalized_locator" => "two.md"
    )
  end

  it "exposes bounded forward and reverse relationship traversal through MCP", :read_model do
    parent = create(:coordinator_read_development_artifact, title: "Parent", source_locator: "docs/mcp.md")
    child = create(:coordinator_read_development_artifact, title: "Child", source_locator: "docs/child.md")
    create(:coordinator_read_development_artifact_observation, artifact: parent)
    create(:coordinator_read_development_artifact_observation, artifact: child)
    create(
      :coordinator_read_development_artifact_relation,
      source_artifact: parent,
      target_id: child.artifact_id,
      path: "child.md"
    )

    outgoing = call_tool(
      "development_artifact_relation_list",
      { artifact_id: parent.artifact_id, direction: "outgoing", limit: 10 },
      id: 4
    ).dig("result", "structuredContent", "data", "page")
    incoming = call_tool(
      "development_artifact_relation_list",
      { artifact_id: child.artifact_id, direction: "incoming", limit: 10 },
      id: 5
    ).dig("result", "structuredContent", "data", "page")

    expect(outgoing.fetch("items").sole).to include(
      "direction" => "outgoing",
      "peer_id" => child.artifact_id,
      "status" => "active",
      "display_relation" => "references",
      "inverse_relation" => "referenced_by",
      "target" => include("status" => "verified"),
      "follow_action" => {
        "tool" => "development_artifact_get",
        "arguments" => { "artifact_id" => child.artifact_id }
      }
    )
    expect(incoming.fetch("items").sole).to include(
      "direction" => "incoming",
      "peer_id" => parent.artifact_id,
      "display_relation" => "referenced_by",
      "follow_action" => {
        "tool" => "development_artifact_get",
        "arguments" => { "artifact_id" => parent.artifact_id }
      }
    )
    expect(outgoing.fetch("continuation_cursor")).to include(
      "after_observed_sequence" => be_positive
    )
  end

  it "records immutable relation correction through MCP Tasks", :event_store do
    parent = capture_through_task(capture_input(command_id: "cmd-mcp-correction-parent"), id: 1)
    original_child = capture_through_task(
      capture_input(
        command_id: "cmd-mcp-correction-original",
        locator: "docs/original.md",
        text: "original child\n"
      ),
      id: 2
    )
    replacement_child = capture_through_task(
      capture_input(
        command_id: "cmd-mcp-correction-replacement",
        locator: "docs/replacement.md",
        text: "replacement child\n"
      ),
      id: 3
    )
    original_task = call_tool(
      "development_artifact_relation_declare",
      {
        command_id: "cmd-mcp-correction-edge-original",
        actor: { kind: "agent", id: "agent-mcp-artifact" },
        source_artifact_id: parent,
        relation: "references",
        target: { kind: "artifact", id: original_child },
        attributes: {
          path: "guide/../docs/original.md",
          fragment: "usage",
          normalized_locator: "docs/original.md"
        }
      },
      id: 4
    ).dig("result", "taskId")
    execute_task(original_task)
    original = task_request("tasks/get", original_task, id: 14)
      .dig("result", "result", "structuredContent", "data")

    replacement_task = call_tool(
      "development_artifact_relation_declare",
      {
        command_id: "cmd-mcp-correction-edge-replacement",
        actor: { kind: "agent", id: "agent-mcp-artifact" },
        source_artifact_id: parent,
        relation: "references",
        target: { kind: "artifact", id: replacement_child },
        attributes: {
          path: "guide/../docs/replacement.md",
          fragment: "usage",
          normalized_locator: "docs/replacement.md"
        },
        supersedes: {
          relation_id: original.fetch("relation_id"),
          reason: "The parent link now names the replacement document."
        }
      },
      id: 5
    ).dig("result", "taskId")
    execute_task(replacement_task)
    replacement = task_request("tasks/get", replacement_task, id: 15)
      .dig("result", "result", "structuredContent", "data")

    expect(replacement).to include(
      "outcome" => "superseded",
      "superseded_relation_id" => original.fetch("relation_id")
    )
    expect(artifact_events(parent).map(&:type)).to eq(
      [
        "DevelopmentArtifactCaptured",
        "DevelopmentArtifactRelationDeclared",
        "DevelopmentArtifactRelationDeclared",
        "DevelopmentArtifactRelationSuperseded"
      ]
    )
  end

  it "serves literal link evidence and projected relation supersession", :read_model do
    parent = create(:coordinator_read_development_artifact, title: "Parent")
    original_child = create(:coordinator_read_development_artifact, title: "Original child")
    replacement_child = create(:coordinator_read_development_artifact, title: "Replacement child")
    [ parent, original_child, replacement_child ].each do |artifact|
      create(:coordinator_read_development_artifact_observation, artifact:)
    end
    original = create(
      :coordinator_read_development_artifact_relation,
      source_artifact: parent,
      target_id: original_child.artifact_id,
      path: "guide/../docs/original.md",
      fragment: "usage",
      normalized_locator: "docs/original.md"
    )
    replacement = create(
      :coordinator_read_development_artifact_relation,
      source_artifact: parent,
      target_id: replacement_child.artifact_id,
      path: "guide/../docs/replacement.md",
      fragment: "usage",
      normalized_locator: "docs/replacement.md"
    )
    create(
      :coordinator_read_development_artifact_relation_supersession,
      relation: original,
      replacement_relation_id: replacement.relation_id,
      reason: "The parent link now names the replacement document."
    )

    page = call_tool(
      "development_artifact_relation_list",
      {
        artifact_id: parent.artifact_id,
        direction: "outgoing",
        include_superseded: true,
        limit: 10
      },
      id: 6
    ).dig("result", "structuredContent", "data", "page")
    by_id = page.fetch("items").index_by { _1.fetch("relation_id") }

    expect(by_id.fetch(original.relation_id)).to include(
      "status" => "superseded",
      "replacement_relation_id" => replacement.relation_id,
      "supersession_reason" => "The parent link now names the replacement document."
    )
    expect(by_id.fetch(replacement.relation_id)).to include(
      "status" => "active",
      "attributes" => include(
        "path" => "guide/../docs/replacement.md",
        "fragment" => "usage",
        "normalized_locator" => "docs/replacement.md"
      )
    )
  end

  def capture_input(
    command_id: "cmd-mcp-artifact",
    locator: "docs/mcp.md",
    text: "MCP artifact body\n"
  )
    {
      command_id:,
      actor: { kind: "agent", id: "agent-mcp-artifact" },
      scope: "project:alpha",
      title: "MCP Artifact",
      kind: "documentation",
      labels: %w[docs mcp],
      content: { encoding: "utf-8", media_type: "text/markdown", text: },
      source: {
        kind: "local_file",
        locator:,
        revision: nil,
        observed_at: "2026-08-25T16:00:00.000000Z",
        collector: "mcp-spec/v1"
      }
    }
  end

  def call_tool(name, arguments, id:)
    mcp_request(id:, method: "tools/call", name:, params: { name:, arguments: })
  end

  def capture_through_task(input, id:)
    task_id = call_tool("development_artifact_capture", input, id:).dig("result", "taskId")
    execute_task(task_id)
    task_request("tasks/get", task_id, id: id + 10)
      .dig("result", "result", "structuredContent", "data", "artifact_id")
  end

  def task_request(method, task_id, id:)
    mcp_request(id:, method:, name: task_id, params: { taskId: task_id })
  end

  def mcp_request(id:, method:, params:, name:)
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id:, method:, params: modern_params(params)),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => ART_PROTOCOL_VERSION,
        "Mcp-Method" => method,
        "Mcp-Name" => name
      }
    )
    expect(session.response.status).to be_between(200, 299), session.response.body
    JSON.parse(session.response.body)
  end

  def modern_params(params)
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => ART_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { ART_TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    )
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
  end

  def run_batch(batch_id)
    created = batch_events(batch_id).find { _1.type == "OperationBatchCreated" }
    Coordinator::Container["process_managers.operation_batch_runner"].call(created)
  end

  def task_events(task_id)
    event_store.read(
      streams.coordination_task(task_id),
      Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY
    )
  end

  def batch_events(batch_id)
    event_store.read(
      streams.operation_batch(batch_id),
      Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY
    )
  end

  def artifact_events(artifact_id)
    event_store.read(
      streams.development_artifact(artifact_id),
      Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_HISTORY
    )
  end

  def observation_events(observation_id)
    event_store.read(
      streams.development_artifact_observation(observation_id),
      Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_OBSERVATION_HISTORY
    )
  end

  def load_completion(command_id)
    event = event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    ).sole
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end
end
