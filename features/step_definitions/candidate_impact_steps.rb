# frozen_string_literal: true

Given("impact ChangeSet {string} has these projected Candidate checkpoints:") do |prefix, table|
  @impact_candidates = prepare_impact_change_set(prefix:, rows: table.hashes)
end

When("analyzer {string} submits this impact evidence for {string}:") do |actor_id, role, table|
  candidate = @impact_candidates.fetch(role)
  @impact_arguments = impact_arguments(
    candidate,
    command_id: "cmd-cuc-impact-#{role}-surface",
    actor_id:,
    surface: surface_from_rows(table.hashes)
  )
  @impact_task_id = submit_impact_task(@impact_arguments)
  @impact_task_state = candidate_task_state(@impact_task_id)
  @impact_role = role
end

Then("the impact Task completes with attributed unverified evidence") do
  result = @impact_task_state.dig("result", "result")
  content = result.fetch("structuredContent")
  assert_acceptance_equal("completed", @impact_task_state.dig("result", "status"), "Impact Task")
  assert_acceptance_equal(false, result.fetch("isError"), "Impact tool error")
  assert_acceptance_equal("ok", content.fetch("status"), "Impact result status")
  assert_acceptance_equal(
    "attributed_unverified",
    content.dig("data", "evidence_status"),
    "Impact attribution status"
  )
end

Then("the surface and successful command lifecycle preserve the Task trace") do
  candidate = @impact_candidates.fetch(@impact_role)
  surface = impact_events(candidate).sole
  terminal = assert_command_succeeded(
    @impact_arguments.fetch(:command_id),
    context: "Impact command lifecycle"
  ).last
  started = task_events(@impact_task_id).find { _1.type == "CoordinationTaskExecutionStarted" }
  completed = task_events(@impact_task_id).find { _1.type == "CoordinationTaskCompleted" }
  assert_acceptance(started, "Impact Task has no execution-started fact")
  assert_acceptance(completed, "Impact Task has no completion fact")
  assert_acceptance_equal(started.id, surface.causation_id, "Impact surface causation")
  assert_acceptance_equal(started.id, terminal.causation_id, "Impact command causation")
  assert_acceptance_equal(terminal.id, completed.causation_id, "Impact Task completion causation")
  assert_acceptance_equal(
    [ started.correlation_id ],
    [ surface, terminal, completed ].map(&:correlation_id).uniq,
    "Impact correlation"
  )
end

Then("the previously observed Candidate is still served without the new surface or a freshness gate") do
  candidate = @impact_candidates.fetch(@impact_role)
  current = candidate_impact_view(candidate.dig(:arguments, :candidate_id))
  assert_acceptance_equal(candidate.fetch(:baseline), current, "Lagging impact view")
  assert_acceptance_equal(nil, current.dig("data", "page", "impact_surface"), "Lagging surface")
  assert_acceptance(
    (current.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Lagging impact view must remain available"
  )
end

When("the {string} impact fact reaches the read side") do |role|
  project_impact(@impact_candidates.fetch(role))
end

Then("the available {string} surface preserves attributed evidence without a freshness claim") do |role|
  page = candidate_impact_view(@impact_candidates.dig(role, :arguments, :candidate_id))
  surface = page.dig("data", "page", "impact_surface")
  assert_acceptance_equal("ok", page.fetch("status"), "Available impact status")
  assert_acceptance_equal("attributed_unverified", surface.fetch("evidence_status"), "Available attribution")
  assert_acceptance_equal("impact-analyzer-v1", surface.dig("analyzer", "analyzer_version"), "Analyzer")
  assert_acceptance(surface.dig("evidence", "causation_id"), "Impact causation is missing")
  assert_acceptance(surface.dig("evidence", "correlation_id"), "Impact correlation is missing")
  assert_acceptance_equal([], page.fetch("warnings"), "Available impact warnings")
  assert_acceptance(
    (page.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Available impact view must not expose freshness"
  )
end

When("these attributed impact surfaces are submitted and projected:") do |table|
  table.hashes.group_by { _1.fetch("role") }.each do |role, rows|
    candidate = @impact_candidates.fetch(role)
    arguments = impact_arguments(
      candidate,
      command_id: "cmd-cuc-impact-match-#{role.tr('_', '-')}",
      actor_id: "analyzer-#{role.tr('_', '-')}",
      surface: surface_from_rows(rows)
    )
    task_id = submit_impact_task(arguments)
    assert_successful_task(task_id, "Impact surface #{role}")
    candidate[:impact_arguments] = arguments
    candidate[:impact_task_id] = task_id
    project_impact(candidate)
  end
end

Then("outgoing potential impacts from {string} page exact path and semantic reasons once") do |role|
  candidate_id = @impact_candidates.dig(role, :arguments, :candidate_id)
  first = candidate_impact_view(candidate_id, limit: 1).dig("data", "page")
  first_relationship = first.fetch("relationships").sole
  second = candidate_impact_view(
    candidate_id,
    limit: 1,
    after_global_position: first.fetch("next_global_position")
  ).dig("data", "page")
  second_relationship = second.fetch("relationships").sole

  assert_acceptance_equal(true, first.fetch("has_more"), "First impact page")
  assert_acceptance_equal(
    "CAN-CUC-IMP-MATCH-PATH",
    first_relationship.dig("counterpart", "candidate_id"),
    "Path counterpart"
  )
  assert_acceptance_equal(
    "potentially_affects",
    first_relationship.fetch("relationship_kind"),
    "Relationship truth language"
  )
  assert_acceptance_equal(
    %w[changed_resource_overlap observed_input_changed semantic_key_match],
    first_relationship.fetch("reasons").map { _1.fetch("kind") },
    "Aggregated impact reasons"
  )
  assert_acceptance_equal(
    [ [ "contracts/payments.json" ], [ "contracts/payments.json" ], [ "contract:payments-api:v2" ] ],
    first_relationship.fetch("reasons").map { _1.fetch("matches") },
    "Exact impact matches"
  )
  assert_acceptance_equal(
    %w[
      CandidateChangeManifestCaptured CandidateChangeManifestCaptured
      CandidateChangeManifestCaptured CandidateBuildContextCaptured
      CandidateImpactSurfaceDerived CandidateImpactSurfaceDerived
    ],
    first_relationship.fetch("reasons").flat_map do |reason|
      [
        reason.dig("source_evidence", "event", "type"),
        reason.dig("target_evidence", "event", "type")
      ]
    end,
    "Exact relationship evidence"
  )
  assert_acceptance_equal(false, second.fetch("has_more"), "Second impact page")
  assert_acceptance_equal(nil, second.fetch("next_global_position"), "Terminal impact cursor")
  assert_acceptance_equal(
    "CAN-CUC-IMP-MATCH-CHECKOUT",
    second_relationship.dig("counterpart", "candidate_id"),
    "Semantic counterpart"
  )
  assert_acceptance_equal(
    [ "semantic_key_match" ],
    second_relationship.fetch("reasons").map { _1.fetch("kind") },
    "Cross-repository reasons"
  )
end

Then(
  "incoming potential impact to {string} points across repositories to {string}"
) do |target_role, source_role|
  target = @impact_candidates.fetch(target_role)
  source = @impact_candidates.fetch(source_role)
  page = candidate_impact_view(
    target.dig(:arguments, :candidate_id),
    direction: "incoming"
  ).dig("data", "page")
  relationship = page.fetch("relationships").sole
  assert_acceptance_equal(
    source.dig(:arguments, :candidate_id),
    relationship.dig("counterpart", "candidate_id"),
    "Incoming semantic source"
  )
  assert_acceptance_equal(
    [ "semantic_key_match" ],
    relationship.fetch("reasons").map { _1.fetch("kind") },
    "Incoming semantic reason"
  )
  assert_acceptance(
    target.dig(:arguments, :repository_id) != source.dig(:arguments, :repository_id),
    "Semantic target must prove a cross-repository match"
  )
end

When("the exact impact command is retried through its original Task") do
  @impact_retry_task_id = submit_impact_task(@impact_arguments)
  @impact_retry_state = candidate_task_state(@impact_retry_task_id)
end

Then("the replayed impact Task exposes the same result") do
  assert_acceptance_equal(@impact_task_id, @impact_retry_task_id, "Replayed impact Task identity")
  assert_acceptance_equal(
    @impact_task_state.dig("result", "result"),
    @impact_retry_state.dig("result", "result"),
    "Impact replay result"
  )
end

Then("{string} has one impact fact and one successful command lifecycle") do |role|
  candidate = @impact_candidates.fetch(role)
  assert_acceptance_equal(1, impact_events(candidate).length, "Impact facts")
  assert_command_succeeded(@impact_arguments.fetch(:command_id), context: "Impact command lifecycle")
end

When("two analyzers concurrently submit different initial surfaces for {string}") do |role|
  candidate = @impact_candidates.fetch(role)
  @impact_race = [
    impact_arguments(
      candidate,
      command_id: "cmd-cuc-impact-race-a",
      actor_id: "analyzer-a",
      surface: surface_from_rows([
        { "direction" => "produces", "impact_key" => "contract:payments-api:v2", "value" => "available" }
      ])
    ),
    impact_arguments(
      candidate,
      command_id: "cmd-cuc-impact-race-b",
      actor_id: "analyzer-b",
      surface: surface_from_rows([
        { "direction" => "may_affect", "impact_key" => "framework:rails:callbacks", "value" => "" }
      ])
    )
  ].map do |arguments|
    { arguments:, task_id: submit_impact_task(arguments, execute: false) }
  end
  @impact_race.map do |entry|
    Thread.new { execute_task(entry.fetch(:task_id)) }
  end.each(&:value)
  @impact_race.each do |entry|
    entry[:state] = candidate_task_state(entry.fetch(:task_id))
    entry[:content] = entry.dig(:state, "result", "result", "structuredContent")
  end
  @impact_role = role
end

Then("one impact Task succeeds and the other reports an already-recorded surface") do
  assert_acceptance(
    @impact_race.all? { _1.dig(:state, "result", "status") == "completed" },
    "Both impact race Tasks must complete"
  )
  assert_acceptance_equal(
    [ "conflict", "ok" ],
    @impact_race.map { _1.dig(:content, "status") }.sort,
    "Impact race outcomes"
  )
  @impact_race_winner = @impact_race.find { _1.dig(:content, "status") == "ok" }
  @impact_race_loser = @impact_race.find { _1.dig(:content, "status") == "conflict" }
  assert_acceptance_equal(
    "candidate_impact_surface_already_recorded",
    @impact_race_loser.dig(:content, "data", "code"),
    "Impact race denial"
  )
end

Then("only the winning impact command has target facts") do
  candidate = @impact_candidates.fetch(@impact_role)
  winner_command = @impact_race_winner.dig(:arguments, :command_id)
  loser_command = @impact_race_loser.dig(:arguments, :command_id)
  assert_acceptance_equal(1, impact_events(candidate).length, "Race impact facts")
  assert_command_succeeded(winner_command, context: "Winning impact command lifecycle")
  assert_command_rejected(loser_command, context: "Losing impact command lifecycle")
end

When("the analyzer attempts to submit an empty impact surface for {string}") do |role|
  candidate = @impact_candidates.fetch(role)
  @impact_arguments = impact_arguments(
    candidate,
    command_id: "cmd-cuc-impact-invalid",
    actor_id: "analyzer-invalid",
    surface: { produces: [], consumes: [], may_affect: [], assumes: [] }
  )
  @impact_invalid_response = call_tool(
    "candidate_impact_surface_submit",
    @impact_arguments,
    expected_status: 400
  )
  @impact_role = role
end

Then("the impact request is rejected before Task allocation") do
  assert_acceptance_equal(-32_602, @impact_invalid_response.dig("error", "code"), "Impact JSON-RPC error")
  assert_acceptance_equal(
    "invalid_input",
    @impact_invalid_response.dig("error", "data", "code"),
    "Impact input error"
  )
  assert_acceptance_equal(
    [],
    task_events_for_command(@impact_arguments.fetch(:command_id)),
    "Invalid impact Task submissions"
  )
end

Then("{string} has no impact facts or command lifecycle") do |role|
  assert_acceptance_equal([], impact_events(@impact_candidates.fetch(role)), "Invalid impact facts")
  assert_acceptance_equal([], command_events(@impact_arguments.fetch(:command_id)), "Invalid impact completion")
end
