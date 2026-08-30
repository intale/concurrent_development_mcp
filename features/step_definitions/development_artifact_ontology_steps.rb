# frozen_string_literal: true

When("the agent captures identical documentation bytes from two Git revisions") do
  @historical_artifact_captures = %w[commit-a commit-b].each_with_index.map do |revision, index|
    capture_artifact_task(
      command_id: "cmd-cuc-artifact-observation-#{index}",
      title: "Unchanged guide",
      kind: "documentation",
      labels: %w[docs historical],
      locator: "docs/unchanged.md",
      source_kind: "local_file",
      revision:,
      content: {
        encoding: "utf-8",
        media_type: "text/markdown",
        text: "unchanged documentation\n"
      }
    ).fetch("data")
  end
end

Then("both capture Tasks name one content-addressed Artifact and two observation IDs") do
  assert_acceptance_equal(
    1,
    @historical_artifact_captures.map { _1.fetch("artifact_id") }.uniq.length,
    "Content-addressed Artifact IDs"
  )
  assert_acceptance_equal(
    2,
    @historical_artifact_captures.map { _1.fetch("observation_id") }.uniq.length,
    "Historical observation IDs"
  )
end

When("both Artifact observations reach the read side") do
  @historical_artifact_views = @historical_artifact_captures.map do |capture|
    project_artifact(
      capture.fetch("artifact_id"),
      observation_id: capture.fetch("observation_id")
    )
  end
end

Then("exact observation actions retrieve both Git revisions independently") do
  revisions = @historical_artifact_views.map do |view|
    view.dig("data", "artifact", "artifact", "source", "revision")
  end
  assert_acceptance_equal(%w[commit-a commit-b], revisions, "Exact historical revisions")
end

Then("both observations lead to the same passive content") do
  artifact_ids = @historical_artifact_captures.map { _1.fetch("artifact_id") }.uniq
  content = artifact_content(artifact_ids.sole).dig("data", "content")
  assert_acceptance_equal("unchanged documentation\n", content.fetch("text"), "Passive content")
  assert_acceptance_equal(
    1,
    @historical_artifact_views.map do |view|
      view.dig("data", "artifact", "artifact", "content_sha256")
    end.uniq.length,
    "Historical content digests"
  )
end

Given("one projected documentation observation has an inaccurate title and labels") do
  capture = capture_artifact_task(
    command_id: "cmd-cuc-artifact-classification-capture",
    title: "Temporary title",
    kind: "documentation",
    labels: %w[temporary inaccurate],
    locator: "docs/classification.md",
    source_kind: "local_file",
    revision: "classification-commit",
    content: {
      encoding: "utf-8",
      media_type: "text/markdown",
      text: "classification evidence\n"
    }
  ).fetch("data")
  @classification_artifact_id = capture.fetch("artifact_id")
  @classification_observation_id = capture.fetch("observation_id")
  projected = project_artifact(
    @classification_artifact_id,
    observation_id: @classification_observation_id
  )
  @classification_before = projected.dig("data", "artifact", "artifact")
end

When("the agent corrects that observation classification through a Task") do
  @classification_task_id = submit_and_execute(
    "development_artifact_classification_correct",
    command_id: "cmd-cuc-artifact-classification-correct",
    actor: { kind: "agent", id: "classification-agent" },
    observation_id: @classification_observation_id,
    expected_revision: 1,
    title: "Authoritative coordination contract",
    kind: "contract",
    labels: %w[authoritative coordination],
    reason: "The immutable bytes define the coordination contract."
  )
  @classification_outcome = task_request("tasks/get", @classification_task_id)
    .dig("result", "result", "structuredContent")
end

Then("the correction advances the classification revision without capturing new bytes") do
  assert_acceptance_equal(2, @classification_outcome.dig("data", "classification_revision"), "Revision")
  captures = artifact_events(@classification_artifact_id).count do |event|
    event.type == "DevelopmentArtifactCaptured"
  end
  assert_acceptance_equal(1, captures, "Immutable Artifact capture facts")
end

Then("exact observation retrieval exposes the corrected title and labels") do
  projected = await_read_model("Corrected Artifact classification to become available") do
    payload = artifact_view(
      @classification_artifact_id,
      observation_id: @classification_observation_id
    )
    revision = payload.dig("data", "artifact", "artifact", "classification_revision")
    [ revision == 2, payload ]
  end
  @classification_after = projected.dig("data", "artifact", "artifact")
  assert_acceptance_equal(
    "Authoritative coordination contract",
    @classification_after.fetch("title"),
    "Corrected title"
  )
  assert_acceptance_equal(
    %w[authoritative coordination],
    @classification_after.fetch("labels"),
    "Corrected labels"
  )
end

Then("its content digest and immutable provenance are unchanged") do
  assert_acceptance_equal(
    @classification_before.fetch("content_sha256"),
    @classification_after.fetch("content_sha256"),
    "Content digest"
  )
  assert_acceptance_equal(
    @classification_before.fetch("source"),
    @classification_after.fetch("source"),
    "Source provenance"
  )
end

Given("a projected source Artifact is available for target validation") do
  @target_validation_source = capture_artifact_task(
    command_id: "cmd-cuc-artifact-target-source",
    title: "Target validation source",
    kind: "documentation",
    labels: %w[target validation],
    locator: "docs/targets.md",
    source_kind: "local_file",
    content: { encoding: "utf-8", media_type: "text/markdown", text: "targets\n" }
  ).dig("data", "artifact_id")
  project_artifact(@target_validation_source)
end

When("the agent declares a relationship to a nonexistent Candidate") do
  outcome = declare_artifact_relation_task(
    command_id: "cmd-cuc-artifact-missing-candidate",
    source_artifact_id: @target_validation_source,
    relation: "documents",
    target: { kind: "candidate", id: "CAN-CUC-DOES-NOT-EXIST" }
  )
  @missing_candidate_relation = outcome.fetch(:result)
end

Then("the relation Task is denied and no relation fact exists") do
  assert_acceptance_equal(
    "development_artifact_target_not_found",
    @missing_candidate_relation.dig("data", "code"),
    "Missing Candidate relation error"
  )
  relation_facts = artifact_events(@target_validation_source).count do |event|
    event.type == "DevelopmentArtifactRelationDeclared"
  end
  assert_acceptance_equal(0, relation_facts, "Denied relation facts")
end

When("the agent declares a relationship to an external URL") do
  outcome = declare_artifact_relation_task(
    command_id: "cmd-cuc-artifact-external-target",
    source_artifact_id: @target_validation_source,
    relation: "documents",
    target: { kind: "external", id: "https://example.test/contracts/current" }
  )
  @external_relation_outcome = outcome.fetch(:result)
  @external_relation_id = @external_relation_outcome.dig("data", "relation_id")
  @external_relation_page = await_artifact_relation(
    @target_validation_source,
    relation_id: @external_relation_id,
    status: "active"
  )
end

Then("the relation is accepted with an unverified target status") do
  assert_acceptance_equal("ok", @external_relation_outcome.fetch("status"), "External relation Task")
  item = @external_relation_page.fetch("items").find do |relation|
    relation.fetch("relation_id") == @external_relation_id
  end
  assert_acceptance_equal("unverified", item.dig("target", "status"), "External target status")
  assert_acceptance_equal(nil, item.fetch("follow_action"), "External follow action")
end

Given("two independent MCP agents know the same projected parent and child Artifacts") do
  prepare_mcp_clients("artifact-agent-a", "artifact-agent-b")
  @direction_parent = capture_artifact_task(
    command_id: "cmd-cuc-artifact-direction-parent",
    title: "Direction parent",
    kind: "documentation",
    labels: %w[direction parent],
    locator: "direction/README.md",
    source_kind: "local_file",
    content: { encoding: "utf-8", media_type: "text/markdown", text: "parent\n" }
  ).dig("data", "artifact_id")
  @direction_child = capture_artifact_task(
    command_id: "cmd-cuc-artifact-direction-child",
    title: "Direction child",
    kind: "documentation",
    labels: %w[direction child],
    locator: "direction/child.md",
    source_kind: "local_file",
    content: { encoding: "utf-8", media_type: "text/markdown", text: "child\n" }
  ).dig("data", "artifact_id")
  project_artifact(@direction_parent)
  project_artifact(@direction_child)
end

When("both agents declare that the parent references the child") do
  @direction_outcomes = %w[a b].map do |suffix|
    declare_artifact_relation_task(
      command_id: "cmd-cuc-artifact-direction-#{suffix}",
      source_artifact_id: @direction_parent,
      relation: "references",
      target: { kind: "artifact", id: @direction_child },
      actor_id: "artifact-agent-#{suffix}",
      client_id: "artifact-agent-#{suffix}"
    ).fetch(:result)
  end
end

Then("both relation Tasks identify one directed edge") do
  relation_ids = @direction_outcomes.map { _1.dig("data", "relation_id") }
  assert_acceptance_equal(1, relation_ids.uniq.length, "Canonical directed relation IDs")
  relation_facts = artifact_events(@direction_parent).count do |event|
    event.type == "DevelopmentArtifactRelationDeclared"
  end
  assert_acceptance_equal(1, relation_facts, "Canonical directed relation facts")
  @direction_relation_id = relation_ids.first
end

Then("outgoing parent traversal and incoming child traversal expose inverse directions") do
  outgoing = await_artifact_relation(
    @direction_parent,
    relation_id: @direction_relation_id,
    status: "active"
  ).fetch("items").sole
  incoming = await_read_model("Incoming canonical Artifact relation") do
    page = artifact_relation_page(@direction_child, direction: "incoming")
    item = page&.fetch("items", [])&.find { _1.fetch("relation_id") == @direction_relation_id }
    [ item, page ]
  end.fetch("items").sole
  assert_acceptance_equal("references", outgoing.fetch("display_relation"), "Outgoing relation")
  assert_acceptance_equal("referenced_by", incoming.fetch("display_relation"), "Incoming relation")
  assert_acceptance_equal("references", incoming.fetch("relation"), "Canonical relation")
  assert_acceptance_equal("referenced_by", outgoing.fetch("inverse_relation"), "Canonical inverse")
end

Given("a source Artifact and authoritative coordination targets are available") do
  @follow_source = capture_artifact_task(
    command_id: "cmd-cuc-artifact-follow-source",
    title: "Follow-action source",
    kind: "documentation",
    labels: %w[follow source],
    locator: "follow/source.md",
    source_kind: "local_file",
    content: { encoding: "utf-8", media_type: "text/markdown", text: "follow source\n" }
  ).dig("data", "artifact_id")
  target_artifact = capture_artifact_task(
    command_id: "cmd-cuc-artifact-follow-target",
    title: "Follow-action target",
    kind: "documentation",
    labels: %w[follow target],
    locator: "follow/target.md",
    source_kind: "local_file",
    content: { encoding: "utf-8", media_type: "text/markdown", text: "follow target\n" }
  ).dig("data", "artifact_id")
  project_artifact(@follow_source)
  project_artifact(target_artifact)

  coordination = prepare_discoverable_coordination(
    scope: "project:cucumber-artifact-follow",
    label: "artifact-follow",
    checkpoint: true
  )
  activate_discovery_impact_policy(coordination)
  skill = publish_skill_task(
    name: "artifact-follow-skill",
    scope: "project:cucumber-artifact-follow",
    command_id: "cmd-cuc-artifact-follow-skill",
    expected_revision: 0,
    instructions: "Follow the Artifact relation."
  )
  assert_acceptance_equal("ok", skill.dig(:outcome, "status"), "Follow Skill publication")
  skill_event = skill_events(
    name: "artifact-follow-skill",
    scope: "project:cucumber-artifact-follow"
  ).sole
  project_skill_event(skill_event)

  follow_batch_id = SecureRandom.uuid_v7
  follow_batch_task = submit_and_execute(
    "skill_publish_batch",
    command_id: "cmd-cuc-artifact-follow-batch",
    actor: { kind: "agent", id: "artifact-follow-agent" },
    batch_id: follow_batch_id,
    items: [
      {
        command_id: "cmd-cuc-artifact-follow-batch-item",
        actor: { kind: "agent", id: "artifact-follow-agent" },
        name: "artifact-follow-batch-skill",
        scope: "project:cucumber-artifact-follow",
        expected_revision: 0,
        description: "Batch target",
        instructions: "Provide a durable Batch target.",
        assets: []
      }
    ]
  )
  assert_acceptance(follow_batch_task, "Follow Operation Batch Task")
  await_artifact_relation_batch(follow_batch_id)

  ids = coordination.fetch(:ids)
  @authoritative_relation_targets = {
    "artifact" => { kind: "artifact", id: target_artifact },
    "change_set" => { kind: "change_set", id: ids.fetch(:change_set_id) },
    "work_item" => { kind: "work_item", id: ids.fetch(:work_item_id) },
    "attempt" => { kind: "attempt", id: ids.fetch(:attempt_id) },
    "candidate" => { kind: "candidate", id: coordination.fetch(:candidate_id) },
    "decision" => { kind: "decision", id: coordination.fetch(:decision_id) },
    "skill" => { kind: "skill", id: skill_event.data.fetch("skill_id") },
    "repository" => { kind: "repository", id: coordination.fetch(:repository_id) },
    "operation_batch" => { kind: "operation_batch", id: follow_batch_id }
  }
end

When("the agent declares one documented relationship to each internal target kind") do
  items = @authoritative_relation_targets.each_with_index.map do |(kind, target), index|
    {
      command_id: "cmd-cuc-artifact-follow-relation-#{index}",
      actor: { kind: "agent", id: "artifact-follow-agent" },
      source_artifact_id: @follow_source,
      relation: "documents",
      target:,
      attributes: { path: "targets/#{kind}" }
    }
  end
  @follow_relation_batch = submit_artifact_relation_batch(items, command_suffix: "follow")
  batch = @follow_relation_batch.dig("data", "batch")
  assert_acceptance_equal(items.length, batch.fetch("succeeded"), "Follow relation Batch successes")
  assert_acceptance_equal(0, batch.fetch("rejected"), "Follow relation Batch rejections")
end

When("the internal-target relationships reach the read side") do
  @follow_relation_page = await_artifact_relation_count(
    @follow_source,
    @authoritative_relation_targets.length
  )
end

Then("every relationship supplies an action accepted by its public MCP tool") do
  items = @follow_relation_page.fetch("items")
  assert_acceptance_equal(
    @authoritative_relation_targets.keys.sort,
    items.map { _1.dig("target", "kind") }.sort,
    "Followable target kinds"
  )
  items.each do |relation|
    assert_acceptance_equal("verified", relation.dig("target", "status"), "Verified target")
    action = relation.fetch("follow_action")
    response = call_tool(action.fetch("tool"), action.fetch("arguments"))
    structured = response.dig("result", "structuredContent")
    assert_acceptance(structured, "#{action.fetch('tool')} returned no structured result")
    assert_acceptance_equal("ok", structured.fetch("status"), "#{action.fetch('tool')} status")
  end
end

Given("a source Artifact has reached its active relationship capacity") do
  @capacity_source = capture_artifact_task(
    command_id: "cmd-cuc-artifact-capacity-source",
    title: "Capacity source",
    kind: "verification_evidence",
    labels: %w[capacity bounded],
    locator: "capacity/source.md",
    source_kind: "generated",
    content: { encoding: "utf-8", media_type: "text/markdown", text: "bounded graph\n" }
  ).dig("data", "artifact_id")
  project_artifact(@capacity_source)
  active_limit = Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT
  items = active_limit.times.map do |index|
    artifact_capacity_relation_item(index:, phase: "initial")
  end
  initial = submit_artifact_relation_batch(items, command_suffix: "capacity-initial")
  batch = initial.dig("data", "batch")
  assert_acceptance_equal(active_limit, batch.fetch("succeeded"), "Initial capacity successes")
  manifest = operation_batch_manifest(
    batch_id: batch.fetch("batch_id"),
    limit: Coordinator::Shared::Types::OPERATION_BATCH_QUERY_MAXIMUM_ITEMS
  )
  @capacity_initial_relation_ids = manifest.fetch(:items).sort_by { _1.fetch("index") }.map do |item|
    item.dig("result", "data", "relation_id")
  end
  assert_acceptance_equal(active_limit, @capacity_initial_relation_ids.length, "Initial relation manifest")
  assert_acceptance(@capacity_initial_relation_ids.none?(&:nil?), "Initial relation IDs")
end

When("the agent supersedes one active relationship") do
  outcome = declare_artifact_relation_task(
    command_id: "cmd-cuc-artifact-capacity-first-replacement",
    source_artifact_id: @capacity_source,
    relation: "references",
    target: { kind: "external", id: "https://example.test/capacity/replacement/0" },
    supersedes: {
      relation_id: @capacity_initial_relation_ids.first,
      reason: "Replace one active edge while the active set is full."
    }
  ).fetch(:result)
  assert_acceptance_equal("ok", outcome.fetch("status"), "Capacity replacement Task")
  @capacity_first_replacement_id = outcome.dig("data", "relation_id")
end

Then("active graph capacity remains available for one replacement edge") do
  active_limit = Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT
  artifact = await_read_model(
    "Artifact replacement and supersession to converge",
    timeout_seconds: LiveSubscriptions::HIGH_VOLUME_TIMEOUT_SECONDS
  ) do
    observed = artifact_view(@capacity_source).dig("data", "artifact", "artifact")
    capacity = observed&.fetch("relationship_capacity", nil)
    [
      capacity&.fetch("active_count", nil) == active_limit &&
        capacity&.fetch("lifetime_count", nil) == active_limit + 1,
      observed
    ]
  end
  assert_acceptance_equal(
    active_limit,
    artifact.dig("relationship_capacity", "active_count"),
    "Active relation count after replacement"
  )
end

Then("Artifact metadata reports active and lifetime capacity separately") do
  summary = artifact_view(@capacity_source).dig("data", "artifact", "artifact")
  capacity = summary.fetch("relationship_capacity")
  assert_acceptance_equal(128, capacity.fetch("active_count"), "Active capacity count")
  assert_acceptance_equal(128, capacity.fetch("active_limit"), "Active capacity limit")
  assert_acceptance_equal(129, capacity.fetch("lifetime_count"), "Lifetime capacity count")
  assert_acceptance_equal(256, capacity.fetch("lifetime_limit"), "Lifetime capacity limit")
end

When("another declaration would exceed the lifetime graph limit") do
  remaining_ids = @capacity_initial_relation_ids.drop(1)
  items = remaining_ids.each_with_index.map do |relation_id, index|
    artifact_capacity_relation_item(
      index: index + 1,
      phase: "replacement",
      supersedes_relation_id: relation_id
    )
  end
  history = submit_artifact_relation_batch(items, command_suffix: "capacity-history")
  batch = history.dig("data", "batch")
  assert_acceptance_equal(items.length, batch.fetch("succeeded"), "Lifetime fill successes")
  @capacity_overflow = declare_artifact_relation_task(
    command_id: "cmd-cuc-artifact-capacity-overflow",
    source_artifact_id: @capacity_source,
    relation: "references",
    target: { kind: "external", id: "https://example.test/capacity/overflow" }
  ).fetch(:result)
end

Then("it is denied from bounded history with the discoverable lifetime limit") do
  assert_acceptance_equal(
    "development_artifact_relation_limit_reached",
    @capacity_overflow.dig("data", "code"),
    "Lifetime overflow code"
  )
  details = @capacity_overflow.dig("data", "details")
  assert_acceptance_equal("lifetime", details.fetch("limit_kind"), "Lifetime limit kind")
  assert_acceptance_equal(256, details.fetch("lifetime_maximum"), "Lifetime maximum")
  assert_acceptance_equal(0, details.fetch("lifetime_remaining"), "Lifetime remaining")
  declarations = artifact_events(@capacity_source).count do |event|
    event.type == "DevelopmentArtifactRelationDeclared"
  end
  assert_acceptance_equal(256, declarations, "Bounded declaration history")
end

def artifact_capacity_relation_item(index:, phase:, supersedes_relation_id: nil)
  item = {
    command_id: "cmd-cuc-artifact-capacity-#{phase}-#{index}",
    actor: { kind: "agent", id: "artifact-capacity-agent" },
    source_artifact_id: @capacity_source,
    relation: "references",
    target: {
      kind: "external",
      id: "https://example.test/capacity/#{phase}/#{index}"
    },
    attributes: {}
  }
  if supersedes_relation_id
    item[:supersedes] = {
      relation_id: supersedes_relation_id,
      reason: "Replace active edge #{index} while filling bounded history."
    }
  end
  item
end
