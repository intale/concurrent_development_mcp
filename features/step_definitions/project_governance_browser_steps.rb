# frozen_string_literal: true

PROJECT_GOVERNANCE_COLLECTIONS_QUERY = <<~GRAPHQL.freeze
  query ProjectGovernanceCollections($projectRef: ID!, $decisionAfter: String) {
    projectDecisions(projectRef: $projectRef, first: 50, after: $decisionAfter) {
      nodes { id topicId policyStatus scope { repositoryIds attemptId } }
    }
    projectGuidanceMessages(projectRef: $projectRef, first: 50) {
      nodes { id source anchors { repositoryIds attemptId } }
    }
    projectAgentChoices(projectRef: $projectRef, first: 50) {
      nodes { id observationStatus context { repositoryId attemptId } }
    }
    projectDecisionImpacts(projectRef: $projectRef, first: 50) {
      nodes { assessmentId choiceId attemptId outcome decisionId }
    }
  }
GRAPHQL

PROJECT_GOVERNANCE_DECISION_QUERY = <<~GRAPHQL.freeze
  query ProjectGovernanceDecision($projectRef: ID!, $decisionId: ID!) {
    projectDecision(projectRef: $projectRef, decisionId: $decisionId) {
      membershipBases
      decision { id topicId scope { repositoryIds attemptId } }
    }
  }
GRAPHQL

PROJECT_GOVERNANCE_DETAILS_QUERY = <<~GRAPHQL.freeze
  query ProjectGovernanceDetails(
    $projectRef: ID!
    $messageId: ID!
    $choiceId: ID!
    $assessmentId: ID!
  ) {
    projectGuidance(projectRef: $projectRef, messageId: $messageId) {
      guidance { id text source }
      interpretations { nodes { id messageId topicId assessmentStatus value { schema name } } }
    }
    projectAgentChoice(projectRef: $projectRef, choiceId: $choiceId) {
      choice { id observationStatus selected { id summary } }
      impacts { nodes { assessmentId choiceId outcome decisionId beforeStatus afterStatus } }
    }
    projectDecisionImpact(projectRef: $projectRef, assessmentId: $assessmentId) {
      impact { assessmentId choiceId outcome decisionId beforeStatus afterStatus }
    }
  }
GRAPHQL

PROJECT_GOVERNANCE_ISOLATED_FAILURE_QUERY = <<~GRAPHQL.freeze
  query ProjectGovernanceIsolatedFailure($projectRef: ID!) {
    projectDecisions(projectRef: $projectRef, first: 20, after: "not-a-cursor") { nodes { id } }
    projectGuidanceMessages(projectRef: $projectRef, first: 20) { nodes { id text } }
  }
GRAPHQL

Given("projected governance rows retain an old Attempt Decision outside the bounded context window") do
  create_governance_browser_project
  create_governance_coordination_history
  context = Coordinator::Read::CoordContext.find(governance_change_set_id)
  context.update!(document: context.document.merge("attempts" => []))
  FactoryBot.create(
    :coordinator_read_decision_definition,
    decision_id: governance_decision_id,
    repository_id: nil,
    attempt_id: governance_attempt_id,
    topic_id: "testing.framework"
  )
end

When("the browser opens the focused Decision collection and detail") do
  @governance_collections_payload = query_project_governance(
    PROJECT_GOVERNANCE_COLLECTIONS_QUERY,
    projectRef: @governance_browser_project_ref
  )
  @governance_decision_payload = query_project_governance(
    PROJECT_GOVERNANCE_DECISION_QUERY,
    projectRef: @governance_browser_project_ref,
    decisionId: governance_decision_id
  )
end

Then("the old Decision is presented with Attempt membership provenance") do
  decisions = governance_browser_data(@governance_collections_payload).dig("projectDecisions", "nodes")
  detail = governance_browser_data(@governance_decision_payload).fetch("projectDecision")

  assert_acceptance_equal([ governance_decision_id ], decisions.map { _1.fetch("id") }, "Decisions")
  assert_acceptance_equal([ "attempt" ], detail.fetch("membershipBases"), "Decision membership")
  assert_acceptance_equal(governance_attempt_id, detail.dig("decision", "scope", "attemptId"), "Attempt scope")
end

Given("projected governance rows span two Project members and an unrelated Project") do
  create_governance_browser_project
  create_governance_coordination_history
  member_repository_id = SecureRandom.uuid_v7
  other_repository_id = SecureRandom.uuid_v7
  FactoryBot.create(
    :coordinator_read_repository,
    repository_id: member_repository_id,
    repository_key: "governance-member-#{member_repository_id}",
    scope: @governance_browser_scope
  )
  FactoryBot.create(
    :coordinator_read_repository,
    repository_id: other_repository_id,
    repository_key: "governance-other-#{other_repository_id}",
    scope: "project:test/governance-other-#{other_repository_id}"
  )
  FactoryBot.create(
    :coordinator_read_user_utterance,
    message_id: governance_message_id,
    conversation_id: "C-governance-browser",
    text: "Use the accepted testing boundary.",
    anchors: governance_anchors(member_repository_id)
  )
  FactoryBot.create(
    :coordinator_read_decision_interpretation,
    interpretation_id: governance_interpretation_id,
    message_id: governance_message_id
  )
  FactoryBot.create(
    :coordinator_read_user_utterance,
    message_id: "M-governance-other",
    conversation_id: "C-governance-other",
    anchors: governance_anchors(other_repository_id)
  )
  FactoryBot.create(
    :coordinator_read_agent_choice,
    :accepted,
    choice_id: governance_choice_id,
    context: governance_choice_context(@governance_browser_repository_id, governance_attempt_id)
  )
  FactoryBot.create(
    :coordinator_read_agent_choice,
    :accepted,
    choice_id: "CHO-governance-other",
    context: governance_choice_context(other_repository_id, "A-governance-other")
  )
  FactoryBot.create(
    :coordinator_read_agent_choice_impact,
    assessment_id: governance_impact_id,
    choice_id: governance_choice_id,
    attempt_id: governance_attempt_id
  )
end

When("the browser opens each focused Governance collection and detail") do
  @governance_collections_payload = query_project_governance(
    PROJECT_GOVERNANCE_COLLECTIONS_QUERY,
    projectRef: @governance_browser_project_ref
  )
  @governance_details_payload = query_project_governance(
    PROJECT_GOVERNANCE_DETAILS_QUERY,
    projectRef: @governance_browser_project_ref,
    messageId: governance_message_id,
    choiceId: governance_choice_id,
    assessmentId: governance_impact_id
  )
end

Then("only typed Governance facts associated with the exact Project are presented") do
  catalog = governance_browser_data(@governance_collections_payload)
  detail = governance_browser_data(@governance_details_payload)

  assert_acceptance_equal([ governance_message_id ], catalog.dig("projectGuidanceMessages", "nodes").map { _1.fetch("id") }, "Guidance")
  assert_acceptance_equal([ governance_choice_id ], catalog.dig("projectAgentChoices", "nodes").map { _1.fetch("id") }, "AgentChoices")
  assert_acceptance_equal([ governance_impact_id ], catalog.dig("projectDecisionImpacts", "nodes").map { _1.fetch("assessmentId") }, "Impacts")
  assert_acceptance_equal(
    [ [ governance_interpretation_id, "testing.framework", "accepted_for_activation", "named-choice/v1" ] ],
    detail.dig("projectGuidance", "interpretations", "nodes").map do |item|
      [ item.fetch("id"), item.fetch("topicId"), item.fetch("assessmentStatus"), item.dig("value", "schema") ]
    end,
    "Typed interpretations"
  )
  impact = detail.dig("projectDecisionImpact", "impact")
  assert_acceptance_equal(governance_impact_id, impact.fetch("assessmentId"), "Dedicated impact")
  assert_acceptance_equal([ "allowed", "blocked" ], impact.values_at("beforeStatus", "afterStatus"), "Impact transition")
end

Given("projected Governance rows contain available Guidance") do
  create_governance_browser_project
  FactoryBot.create(
    :coordinator_read_user_utterance,
    message_id: governance_message_id,
    conversation_id: "C-governance-browser",
    text: "Available despite an unrelated collection failure.",
    anchors: governance_anchors(@governance_browser_repository_id)
  )
end

When("one Governance collection receives a malformed cursor") do
  @governance_isolation_payload = query_project_governance(
    PROJECT_GOVERNANCE_ISOLATED_FAILURE_QUERY,
    projectRef: @governance_browser_project_ref
  )
end

Then("the failing collection is isolated and the available Guidance is returned") do
  errors = @governance_isolation_payload.fetch("errors")
  data = @governance_isolation_payload.fetch("data")

  assert_acceptance_equal("INVALID_CURSOR", errors.first.dig("extensions", "code"), "Cursor error")
  assert_acceptance_equal([ "projectDecisions" ], errors.first.fetch("path"), "Failure path")
  assert_acceptance(data.fetch("projectDecisions").nil?, "The invalid Decision collection should be null")
  assert_acceptance_equal(
    [ governance_message_id ],
    data.dig("projectGuidanceMessages", "nodes").map { _1.fetch("id") },
    "Available Guidance"
  )
end

def create_governance_browser_project
  @governance_browser_repository_id ||= SecureRandom.uuid_v7
  @governance_browser_scope ||= "project:test/governance-browser-#{@governance_browser_repository_id}"
  @governance_browser_project_ref ||= Coordinator::Read::Web::ProjectReference.new.encode(
    scope: @governance_browser_scope
  )
  return if Coordinator::Read::Repository.exists?(repository_id: @governance_browser_repository_id)

  FactoryBot.create(
    :coordinator_read_repository,
    repository_id: @governance_browser_repository_id,
    repository_key: "governance-browser-#{@governance_browser_repository_id}",
    scope: @governance_browser_scope,
    display_name: "Governance browser"
  )
end

def create_governance_coordination_history
  FactoryBot.create(
    :coordinator_read_coord_context,
    change_set_id: governance_change_set_id,
    work_item_id: governance_work_item_id,
    repository_id: @governance_browser_repository_id
  )
  FactoryBot.create(
    :coordinator_read_attempt_history,
    attempt_id: governance_attempt_id,
    change_set_id: governance_change_set_id,
    work_item_id: governance_work_item_id
  )
end

def governance_anchors(repository_id)
  {
    "repository_ids" => [ repository_id ],
    "change_set_id" => nil,
    "work_item_id" => nil,
    "attempt_id" => nil
  }
end

def governance_choice_context(repository_id, attempt_id)
  {
    "workspace_id" => nil,
    "repository_id" => repository_id,
    "change_set_id" => governance_change_set_id,
    "work_item_id" => governance_work_item_id,
    "attempt_id" => attempt_id,
    "phase" => "implementation",
    "language" => "ruby",
    "paths" => [ "spec/requests/graphql" ],
    "environment" => "test",
    "agent_role" => "implementer"
  }
end

def query_project_governance(query, variables = {})
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! "localhost"
  session.post("/graphql", params: { query:, variables: }, as: :json)
  assert_acceptance(session.response.status == 200, "Governance GraphQL returned HTTP #{session.response.status}")
  JSON.parse(session.response.body)
end

def governance_browser_data(payload)
  errors = payload.fetch("errors", [])
  assert_acceptance(errors.empty?, "Governance GraphQL failed: #{errors.inspect}")
  payload.fetch("data")
end

def governance_change_set_id = "CS-governance-browser"
def governance_work_item_id = "W-governance-browser"
def governance_attempt_id = "A-governance-browser-history"
def governance_decision_id = "D-governance-history"
def governance_message_id = "M-governance-browser"
def governance_interpretation_id = "I-governance-browser"
def governance_choice_id = "CHO-governance-browser"
def governance_impact_id = "choice-impact-v1:#{'7' * 64}"
