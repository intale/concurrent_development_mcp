# frozen_string_literal: true

Given(
  "Candidate coordination {string} gives agent {string} an active lease on {string}"
) do |prefix, agent_id, path|
  @candidate_coordination = prepare_candidate_coordination(prefix:, agent_id:, path:)
end

When(
  "the agent submits Candidate {string} with command {string} at head {string} and build context"
) do |candidate_id, command_id, head_character|
  @candidate_arguments = candidate_arguments(
    @candidate_coordination,
    candidate_id:,
    command_id:,
    head_character:,
    build_context: true
  )
  @candidate_task_id = submit_candidate_task(@candidate_arguments)
  @candidate_task_state = candidate_task_state(@candidate_task_id)
end

When(
  "the agent submits Candidate {string} with command {string} at head {string} without build context"
) do |candidate_id, command_id, head_character|
  @candidate_arguments = candidate_arguments(
    @candidate_coordination,
    candidate_id:,
    command_id:,
    head_character:,
    build_context: false
  )
  @candidate_task_id = submit_candidate_task(@candidate_arguments)
  @candidate_task_state = candidate_task_state(@candidate_task_id)
end

Then("the Candidate Task completes with an attributed unverified checkpoint") do
  result = @candidate_task_state.dig("result", "result")
  content = result.fetch("structuredContent")
  assert_acceptance_equal("completed", @candidate_task_state.dig("result", "status"), "Candidate Task")
  assert_acceptance_equal(false, result.fetch("isError"), "Candidate tool error")
  assert_acceptance_equal("ok", content.fetch("status"), "Candidate result status")
  assert_acceptance_equal(
    "attributed_unverified",
    content.dig("data", "evidence_status"),
    "Candidate attribution status"
  )
  assert_acceptance_equal(
    @candidate_arguments.fetch(:candidate_id),
    content.dig("data", "candidate_id"),
    "Candidate result identity"
  )
end

Then(
  "Candidate {string} has one traced atomic checkpoint with manifest and build context"
) do |candidate_id|
  candidate_facts = candidate_events(candidate_id)
  head_facts = candidate_head_events(
    repository_id: @candidate_arguments.fetch(:repository_id),
    head_commit_oid: @candidate_arguments.fetch(:head_commit_oid)
  )
  attachment_facts = candidate_attachment_events(
    @candidate_arguments.fetch(:attempt_id)
  ).select { _1.data.fetch("candidate_id") == candidate_id }
  completion_facts = command_events(@candidate_arguments.fetch(:command_id))
  started = task_events(@candidate_task_id).find do |event|
    event.type == "CoordinationTaskExecutionStarted"
  end
  assert_acceptance(started, "Candidate Task has no started fact")

  assert_acceptance_equal(
    %w[CandidateSubmitted CandidateChangeManifestCaptured CandidateBuildContextCaptured],
    candidate_facts.map(&:type),
    "Candidate stream facts"
  )
  assert_acceptance_equal(1, head_facts.length, "Candidate head registrations")
  assert_acceptance_equal(1, attachment_facts.length, "Candidate Attempt attachments")
  assert_acceptance_equal(1, completion_facts.length, "Candidate command completions")

  target_facts = [ *candidate_facts, *head_facts, *attachment_facts, *completion_facts ]
  assert_acceptance_equal([ started.id ], target_facts.map(&:causation_id).uniq, "Candidate causation")
  assert_acceptance_equal(
    [ started.correlation_id ],
    target_facts.map(&:correlation_id).uniq,
    "Candidate correlation"
  )
end

Then("Candidate {string} is honestly not observed before projection") do |candidate_id|
  payload = candidate_view(candidate_id)
  assert_acceptance_equal("not_found", payload.fetch("status"), "Unobserved Candidate status")
  assert_acceptance_equal(
    "candidate_not_observed",
    payload.dig("data", "code"),
    "Unobserved Candidate code"
  )
end

When("the Candidate {string} submission reaches the read side") do |candidate_id|
  project_candidate_submission(candidate_id)
end

Then(
  "available Candidate {string} exposes identity while later evidence is unobserved"
) do |candidate_id|
  payload = candidate_view(candidate_id)
  candidate = payload.dig("data", "candidate")
  assert_acceptance_equal("ok", payload.fetch("status"), "Partial Candidate status")
  assert_acceptance_equal(candidate_id, candidate.fetch("candidate_id"), "Partial Candidate identity")
  assert_acceptance_equal(nil, candidate.fetch("manifest"), "Partial Candidate manifest")
  assert_acceptance_equal(nil, candidate.fetch("build_context"), "Partial Candidate build context")
  assert_acceptance_equal(2, payload.fetch("warnings").length, "Partial Candidate warnings")
  assert_acceptance(
    (candidate.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Partial Candidate must not expose a freshness gate"
  )
end

When(
  "the (remaining )Candidate {string} evidence and Attempt attachment reach the read side"
) do |candidate_id|
  project_complete_candidate(candidate_id, @candidate_coordination.dig(:ids, :attempt_id))
end

Then(
  "available Candidate {string} preserves evidence and Attempt context without a freshness claim"
) do |candidate_id|
  payload = candidate_view(candidate_id)
  candidate = payload.dig("data", "candidate")
  page = candidate_page(@candidate_coordination.dig(:ids, :attempt_id))
  context = candidate_context(@candidate_coordination.dig(:ids, :attempt_id))
  checkpoint = context.dig("data", "context", "candidate_checkpoints").sole

  assert_acceptance_equal("ok", payload.fetch("status"), "Available Candidate status")
  assert_acceptance_equal([], payload.fetch("warnings"), "Available Candidate warnings")
  assert_acceptance_equal(
    candidate.fetch("manifest_digest"),
    candidate.dig("manifest", "digest"),
    "Observed manifest digest"
  )
  assert_acceptance_equal(
    candidate.fetch("build_context_digest"),
    candidate.dig("build_context", "digest"),
    "Observed build-context digest"
  )
  assert_acceptance_equal("attributed_unverified", candidate.fetch("evidence_status"), "Attribution")
  assert_acceptance(candidate.dig("submitted", "causation_id"), "Submission causation is missing")
  assert_acceptance(candidate.dig("submitted", "correlation_id"), "Submission correlation is missing")
  assert_acceptance_equal([ candidate_id ], page.fetch("items").map { _1.fetch("candidate_id") }, "Page")
  assert_acceptance_equal(candidate_id, checkpoint.fetch("candidate_id"), "Attempt checkpoint")
  assert_acceptance(
    (candidate.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Candidate must not expose a freshness gate"
  )
  assert_acceptance(
    (context.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Candidate context must not expose a freshness gate"
  )
end

When("the exact Candidate command is retried through another Task") do
  @candidate_retry_task_id = submit_candidate_task(@candidate_arguments)
  @candidate_retry_state = candidate_task_state(@candidate_retry_task_id)
end

Then("both Candidate Tasks complete with the same result") do
  assert_acceptance(
    @candidate_task_id != @candidate_retry_task_id,
    "Exact Candidate retry must receive another Task handle"
  )
  assert_acceptance_equal("completed", @candidate_task_state.dig("result", "status"), "First Task")
  assert_acceptance_equal("completed", @candidate_retry_state.dig("result", "status"), "Retry Task")
  assert_acceptance_equal(
    @candidate_task_state.dig("result", "result"),
    @candidate_retry_state.dig("result", "result"),
    "Candidate replay result"
  )
end

Then(
  "Candidate {string} has one submission, manifest, head registration, attachment, and command completion"
) do |candidate_id|
  assert_acceptance_equal(
    %w[CandidateSubmitted CandidateChangeManifestCaptured],
    candidate_events(candidate_id).map(&:type),
    "Replayed Candidate facts"
  )
  assert_acceptance_equal(
    1,
    candidate_head_events(
      repository_id: @candidate_arguments.fetch(:repository_id),
      head_commit_oid: @candidate_arguments.fetch(:head_commit_oid)
    ).length,
    "Replayed head registrations"
  )
  attachments = candidate_attachment_events(@candidate_arguments.fetch(:attempt_id)).select do |event|
    event.data.fetch("candidate_id") == candidate_id
  end
  assert_acceptance_equal(1, attachments.length, "Replayed Candidate attachments")
  assert_acceptance_equal(
    1,
    command_events(@candidate_arguments.fetch(:command_id)).length,
    "Replayed command completions"
  )
end

When("the agent submits Candidate {string} with stale fencing evidence") do |candidate_id|
  @candidate_arguments = candidate_arguments(
    @candidate_coordination,
    candidate_id:,
    command_id: "cmd-cuc-can-stale",
    head_character: "b"
  )
  @candidate_arguments[:leases] = @candidate_arguments.fetch(:leases).map do |reference|
    reference.merge(fencing_token: reference.fetch(:fencing_token) + 1)
  end
  @candidate_task_id = submit_candidate_task(@candidate_arguments)
  @candidate_task_state = candidate_task_state(@candidate_task_id)
end

Then("the Candidate Task completes with conflict {string}") do |code|
  result = @candidate_task_state.dig("result", "result")
  content = result.fetch("structuredContent")
  assert_acceptance_equal("completed", @candidate_task_state.dig("result", "status"), "Denied Task")
  assert_acceptance_equal(true, result.fetch("isError"), "Denied Candidate error flag")
  assert_acceptance_equal("conflict", content.fetch("status"), "Denied Candidate status")
  assert_acceptance_equal(code, content.dig("data", "code"), "Denied Candidate code")
end

Then("denied Candidate {string} writes no target facts") do |candidate_id|
  assert_candidate_target_absent(candidate_id, @candidate_arguments)
end

When("the agent attempts Candidate {string} without lease observations") do |candidate_id|
  @candidate_arguments = candidate_arguments(
    @candidate_coordination,
    candidate_id:,
    command_id: "cmd-cuc-can-invalid",
    head_character: "b"
  ).merge(leases: [])
  @candidate_invalid_response = call_tool("candidate_submit", @candidate_arguments)
end

Then("the Candidate request is rejected before Task allocation") do
  result = @candidate_invalid_response.fetch("result")
  assert_acceptance_equal(true, result.fetch("isError"), "Invalid Candidate error flag")
  assert_acceptance_equal(nil, result["taskId"], "Invalid Candidate Task handle")
  assert_acceptance_equal(
    [],
    task_events_for_command(@candidate_arguments.fetch(:command_id)),
    "Invalid Candidate Task submissions"
  )
end

Then("invalid Candidate {string} writes no target facts") do |candidate_id|
  assert_candidate_target_absent(candidate_id, @candidate_arguments)
end

When("the agent attempts Candidate {string} with {int} changed files") do |candidate_id, count|
  @candidate_arguments = candidate_arguments(
    @candidate_coordination,
    candidate_id:,
    command_id: "cmd-cuc-can-bound",
    head_character: "b"
  )
  @candidate_arguments[:change_manifest][:files] = count.times.map do |index|
    candidate_manifest_file("lib/bound_#{index}.rb")
  end
  @candidate_invalid_response = call_tool("candidate_submit", @candidate_arguments)
end

Then("the Candidate request is rejected and its schema directs the agent to split WorkItems") do
  result = @candidate_invalid_response.fetch("result")
  assert_acceptance_equal(true, result.fetch("isError"), "Invalid Candidate error flag")
  assert_acceptance_equal(nil, result["taskId"], "Invalid Candidate Task handle")
  assert_acceptance_equal(
    [],
    task_events_for_command(@candidate_arguments.fetch(:command_id)),
    "Invalid Candidate Task submissions"
  )

  catalog = mcp_request(method: "tools/list", params: {})
  tool = catalog.dig("result", "tools").find { _1.fetch("name") == "candidate_submit" }
  files = tool.dig("inputSchema", "properties", "change_manifest", "properties", "files")
  assert_acceptance_equal(
    Coordinator::Shared::Types::CANDIDATE_MANIFEST_MAXIMUM_FILE_COUNT,
    files.fetch("maxItems"),
    "Candidate manifest maximum"
  )
  assert_acceptance(
    files.fetch("description").include?("Split larger checkpoints across WorkItems"),
    "Candidate schema must explain how to replan larger work"
  )
end

When("Candidate {string} at head {string} is submitted and fully projected") do |candidate_id, head_character|
  @lag_old_arguments = candidate_arguments(
    @candidate_coordination,
    candidate_id:,
    command_id: "cmd-cuc-can-lag-old",
    head_character:
  )
  @lag_old_task_id = submit_candidate_task(@lag_old_arguments)
  assert_successful_task(@lag_old_task_id, "Older Candidate")
  project_complete_candidate(candidate_id, @candidate_coordination.dig(:ids, :attempt_id))
  @lag_old_page = candidate_page(@candidate_coordination.dig(:ids, :attempt_id))
  @lag_old_context = candidate_context(@candidate_coordination.dig(:ids, :attempt_id))
end

When("newer Candidate {string} at head {string} commits without projection") do |candidate_id, head_character|
  @lag_new_arguments = candidate_arguments(
    @candidate_coordination,
    candidate_id:,
    command_id: "cmd-cuc-can-lag-new",
    head_character:
  )
  @candidate_arguments = @lag_new_arguments
  @lag_new_task_id = submit_candidate_task(@lag_new_arguments)
  assert_successful_task(@lag_new_task_id, "Newer Candidate")
end

Then(
  "the prior Candidate history and Attempt checkpoint remain available while the newer Candidate is unobserved"
) do
  attempt_id = @candidate_coordination.dig(:ids, :attempt_id)
  current_page = candidate_page(attempt_id)
  current_context = candidate_context(attempt_id)
  newer = candidate_view(@lag_new_arguments.fetch(:candidate_id))

  assert_acceptance_equal(@lag_old_page, current_page, "Lagging Candidate history")
  assert_acceptance_equal(
    @lag_old_context.fetch("context_token"),
    current_context.fetch("context_token"),
    "Lagging Candidate context token"
  )
  assert_acceptance_equal(
    @lag_old_arguments.fetch(:candidate_id),
    current_context.dig("data", "context", "candidate_checkpoints").sole.fetch("candidate_id"),
    "Lagging Candidate checkpoint"
  )
  assert_acceptance_equal("not_found", newer.fetch("status"), "New Candidate availability")
  assert_acceptance(
    (current_context.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Lagging Candidate context must remain available"
  )
end

Then(
  "Candidate history includes both checkpoints and Attempt context points to {string} without a freshness claim"
) do |candidate_id|
  attempt_id = @candidate_coordination.dig(:ids, :attempt_id)
  page = candidate_page(attempt_id)
  context = candidate_context(attempt_id)
  checkpoints = context.dig("data", "context", "candidate_checkpoints")
  assert_acceptance_equal(
    [ @lag_old_arguments.fetch(:candidate_id), candidate_id ],
    page.fetch("items").map { _1.fetch("candidate_id") },
    "Available Candidate history"
  )
  assert_acceptance_equal([ candidate_id ], checkpoints.map { _1.fetch("candidate_id") }, "Latest checkpoint")
  assert_acceptance_equal("ok", candidate_view(candidate_id).fetch("status"), "New Candidate availability")
  assert_acceptance(
    (context.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Converged Candidate context must not expose freshness"
  )
end

Given(
  "Candidate coordinations {string} and {string} give two agents independent leases"
) do |first_prefix, second_prefix|
  @candidate_race = [
    prepare_candidate_coordination(
      prefix: first_prefix,
      agent_id: "agent-a",
      path: "lib/race_a.rb",
      project_context: false
    ),
    prepare_candidate_coordination(
      prefix: second_prefix,
      agent_id: "agent-b",
      path: "lib/race_b.rb",
      project_context: false
    )
  ]
end

When("both agents concurrently submit Candidates for the same repository head") do
  @candidate_race = @candidate_race.map.with_index do |coordination, index|
    suffix = index.zero? ? "A" : "B"
    arguments = candidate_arguments(
      coordination,
      candidate_id: "CAN-CUC-RACE-#{suffix}",
      command_id: "cmd-cuc-can-race-#{suffix.downcase}",
      head_character: "f"
    )
    task_id = submit_candidate_task(arguments, execute: false)
    coordination.merge(arguments:, task_id:)
  end
  @candidate_race.map do |entry|
    Thread.new { execute_task(entry.fetch(:task_id)) }
  end.each(&:value)
  @candidate_race.each do |entry|
    entry[:state] = candidate_task_state(entry.fetch(:task_id))
    entry[:content] = entry.dig(:state, "result", "result", "structuredContent")
  end
end

Then("one Candidate Task succeeds and the other reports a registered-head conflict") do
  assert_acceptance(
    @candidate_race.all? { _1.dig(:state, "result", "status") == "completed" },
    "Both competing Candidate Tasks must complete"
  )
  statuses = @candidate_race.map { _1.dig(:content, "status") }
  assert_acceptance_equal([ "conflict", "ok" ], statuses.sort, "Competing Candidate outcomes")
  @candidate_race_winner = @candidate_race.find { _1.dig(:content, "status") == "ok" }
  @candidate_race_loser = @candidate_race.find { _1.dig(:content, "status") == "conflict" }
  assert_acceptance_equal(
    "candidate_head_already_registered",
    @candidate_race_loser.dig(:content, "data", "code"),
    "Competing Candidate denial"
  )
end

Then("the winning Candidate owns one complete checkpoint while the loser owns no target facts") do
  winner = @candidate_race_winner.fetch(:arguments)
  loser = @candidate_race_loser.fetch(:arguments)
  head_facts = candidate_head_events(
    repository_id: winner.fetch(:repository_id),
    head_commit_oid: winner.fetch(:head_commit_oid)
  )
  winner_attachments = candidate_attachment_events(winner.fetch(:attempt_id)).select do |event|
    event.data.fetch("candidate_id") == winner.fetch(:candidate_id)
  end

  assert_acceptance_equal(
    %w[CandidateSubmitted CandidateChangeManifestCaptured],
    candidate_events(winner.fetch(:candidate_id)).map(&:type),
    "Winning Candidate facts"
  )
  assert_acceptance_equal(1, winner_attachments.length, "Winning Candidate attachment")
  assert_acceptance_equal(1, command_events(winner.fetch(:command_id)).length, "Winning completion")
  assert_acceptance_equal(1, head_facts.length, "Head ownership facts")
  assert_acceptance_equal(
    winner.fetch(:candidate_id),
    head_facts.sole.data.fetch("candidate_id"),
    "Head owner Candidate"
  )
  assert_candidate_target_absent(loser.fetch(:candidate_id), loser, expect_head_absent: false)
end
