# frozen_string_literal: true

Given(
  "project scope {string} has an active ChangeSet for two independent 5.6-luna agents"
) do |scope|
  prepare_live_two_luna_project(scope)
end

When("both agents discover the ChangeSet from scope and acquire their WorkItems through MCP") do
  discover_and_acquire_luna_work
end

When("their exclusive parent and shared child work-intention requests reach the real decision boundary concurrently") do
  contend_for_luna_parent_and_child
end

Then("agent A declares the exclusive parent while agent B receives the blocker context") do
  assert_luna_contention_contract
end

Then("agent B can declare a disjoint intention while agent A remains active") do
  assert_acceptance_equal(3, @luna_reservations.length, "Concurrent disjoint reservations")
end

When("both agents persist final Candidate checkpoints through MCP") do
  checkpoint_luna_candidates
end

When("an available stale context is used for a command after its intention set has been withdrawn") do
  demonstrate_luna_ap_lag_and_complete_work
end

Then("the stale context remains available and the authoritative command is rejected") do
  assert_acceptance_equal("ok", @luna_lag_observation.dig(:stale, "status"), "Stale read")
  assert_acceptance_equal(
    "conflict",
    @luna_lag_observation.dig(:renewal, "status"),
    "Stale write"
  )
end

When("the agents persist the project Decision and reusable Skill through MCP") do
  persist_luna_decision_and_skill
end

When("an external verifier merges, verifies, and activates the ReleaseSet through MCP") do
  integrate_and_release_luna_change_set
end

Then("the live ReleaseSet Saga completes the ChangeSet") do
  assert_luna_release_completed_through_live_saga
end

When("a replacement client knows only the project scope and follows public MCP results") do
  reconstruct_luna_project_from_scope
end

Then("it reconstructs Attempts, checkpoints, Decisions, Skills, Artifacts, and the release") do
  assert_complete_luna_reconstruction
end
