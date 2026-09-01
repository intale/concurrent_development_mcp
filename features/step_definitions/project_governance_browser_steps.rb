# frozen_string_literal: true

PROJECT_GOVERNANCE_BROWSER_QUERY = <<~GRAPHQL.freeze
  query ProjectGovernanceBrowser($repositoryId: ID!) {
    projectGovernance(repositoryId: $repositoryId, first: 50) {
      project { id scope }
      decisions { nodes { id topicId policyStatus } }
      guidance { nodes { id source anchors { repositoryIds attemptId } } }
      choices { nodes { id observationStatus context { repositoryId attemptId } } }
      impacts { nodes { assessmentId choiceId attemptId outcome decisionId } }
    }
  }
GRAPHQL

PROJECT_GOVERNANCE_DECISION_QUERY = <<~GRAPHQL.freeze
  query ProjectGovernanceDecision($repositoryId: ID!, $decisionId: ID!) {
    projectDecision(repositoryId: $repositoryId, decisionId: $decisionId) {
      membershipBases
      decision { id topicId scope { repositoryIds attemptId } }
    }
  }
GRAPHQL

PROJECT_GOVERNANCE_DETAILS_QUERY = <<~GRAPHQL.freeze
  query ProjectGovernanceDetails($repositoryId: ID!, $messageId: ID!, $choiceId: ID!) {
    projectGuidance(repositoryId: $repositoryId, messageId: $messageId) {
      guidance { id text source }
      interpretations {
        nodes { id messageId topicId assessmentStatus value { schema name } }
      }
    }
    projectAgentChoice(repositoryId: $repositoryId, choiceId: $choiceId) {
      choice { id observationStatus selected { id summary } }
      impacts {
        nodes { assessmentId choiceId outcome decisionId beforeStatus afterStatus }
      }
    }
  }
GRAPHQL

GLOBAL_COMMAND_RECEIPTS_QUERY = <<~GRAPHQL.freeze
  query GlobalCommandReceipts {
    commandReceipts(first: 50, toolName: "change_set_create") {
      nodes {
        commandId
        toolName
        status
        summary
        receipt
        emittedEvents { id type streamId streamRevision }
      }
    }
  }
GRAPHQL

Given("projected governance rows retain an old Attempt Decision outside the bounded context window") do
  create_governance_browser_project
  context = FactoryBot.create(
    :coordinator_read_coord_context,
    change_set_id: governance_change_set_id,
    work_item_id: governance_work_item_id,
    repository_id: @governance_browser_repository_id
  )
  context.update!(document: context.document.merge("attempts" => []))
  FactoryBot.create(
    :coordinator_read_attempt_history,
    attempt_id: governance_attempt_id,
    change_set_id: governance_change_set_id,
    work_item_id: governance_work_item_id
  )
  FactoryBot.create(
    :coordinator_read_decision_definition,
    decision_id: governance_decision_id,
    repository_id: nil,
    attempt_id: governance_attempt_id,
    topic_id: "testing.framework"
  )
end

When("the browser queries the projected project governance") do
  @governance_browser_payload = query_project_governance(
    PROJECT_GOVERNANCE_BROWSER_QUERY,
    repositoryId: @governance_browser_repository_id
  )
  @governance_decision_payload = query_project_governance(
    PROJECT_GOVERNANCE_DECISION_QUERY,
    repositoryId: @governance_browser_repository_id,
    decisionId: governance_decision_id
  )
end

Then("the old Decision is presented with Attempt membership provenance") do
  decisions = governance_browser_data(@governance_browser_payload)
    .dig("projectGovernance", "decisions", "nodes")
  detail = governance_browser_data(@governance_decision_payload).fetch("projectDecision")

  assert_acceptance_equal([ governance_decision_id ], decisions.map { _1.fetch("id") }, "Decisions")
  assert_acceptance_equal([ "attempt" ], detail.fetch("membershipBases"), "Decision membership")
  assert_acceptance_equal(governance_attempt_id, detail.dig("decision", "scope", "attemptId"), "Attempt scope")
end

Given("projected governance rows contain related and unrelated guidance choices and impacts") do
  create_governance_browser_project
  create_governance_coordination_history
  other_repository_id = SecureRandom.uuid_v7
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
    anchors: governance_anchors(@governance_browser_repository_id)
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

When("the browser queries the projected project governance and related details") do
  @governance_browser_payload = query_project_governance(
    PROJECT_GOVERNANCE_BROWSER_QUERY,
    repositoryId: @governance_browser_repository_id
  )
  @governance_details_payload = query_project_governance(
    PROJECT_GOVERNANCE_DETAILS_QUERY,
    repositoryId: @governance_browser_repository_id,
    messageId: governance_message_id,
    choiceId: governance_choice_id
  )
end

Then("only typed governance facts associated with the exact project are presented") do
  catalog = governance_browser_data(@governance_browser_payload).fetch("projectGovernance")
  detail = governance_browser_data(@governance_details_payload)

  assert_acceptance_equal([ governance_message_id ], catalog.dig("guidance", "nodes").map { _1.fetch("id") }, "Guidance")
  assert_acceptance_equal([ governance_choice_id ], catalog.dig("choices", "nodes").map { _1.fetch("id") }, "AgentChoices")
  assert_acceptance_equal([ governance_impact_id ], catalog.dig("impacts", "nodes").map { _1.fetch("assessmentId") }, "Impacts")
  assert_acceptance_equal(
    [ [ governance_interpretation_id, "testing.framework", "accepted_for_activation", "named-choice/v1" ] ],
    detail.dig("projectGuidance", "interpretations", "nodes").map do |item|
      [ item.fetch("id"), item.fetch("topicId"), item.fetch("assessmentStatus"), item.dig("value", "schema") ]
    end,
    "Typed interpretations"
  )
  impact = detail.dig("projectAgentChoice", "impacts", "nodes").sole
  assert_acceptance_equal(governance_choice_id, impact.fetch("choiceId"), "Impact choice")
  assert_acceptance_equal("INVALIDATED", impact.fetch("outcome"), "Impact outcome")
  assert_acceptance_equal([ "allowed", "blocked" ], impact.values_at("beforeStatus", "afterStatus"), "Impact transition")
end

Given("projected governance rows contain command receipts from separate coordination contexts") do
  create_governance_browser_project
  FactoryBot.create(
    :coordinator_read_command_receipt,
    command_id: "cmd-governance-a",
    tool_name: "change_set_create"
  )
  FactoryBot.create(
    :coordinator_read_command_receipt,
    command_id: "cmd-governance-b",
    tool_name: "change_set_create"
  )
end

When("the browser queries global command receipts from the project governance route") do
  @governance_receipts_payload = query_project_governance(GLOBAL_COMMAND_RECEIPTS_QUERY)
end

Then("both receipts are presented as typed global audit facts without intermediate command content") do
  receipts = governance_browser_data(@governance_receipts_payload).dig("commandReceipts", "nodes")

  assert_acceptance_equal(
    %w[cmd-governance-a cmd-governance-b],
    receipts.map { _1.fetch("commandId") },
    "Global receipts"
  )
  assert_acceptance(
    receipts.all? { _1.keys.sort == %w[commandId emittedEvents receipt status summary toolName].sort },
    "Receipt response leaked an intermediate command representation: #{receipts.inspect}"
  )
  assert_acceptance(
    receipts.all? { _1.fetch("emittedEvents").all? { |event| event.keys.sort == %w[id streamId streamRevision type].sort } },
    "Receipt events are not typed references"
  )
end

def create_governance_browser_project
  @governance_browser_repository_id ||= SecureRandom.uuid_v7
  return if Coordinator::Read::Repository.exists?(repository_id: @governance_browser_repository_id)

  FactoryBot.create(
    :coordinator_read_repository,
    repository_id: @governance_browser_repository_id,
    repository_key: "governance-browser-#{@governance_browser_repository_id}",
    scope: "project:test/governance-browser-#{@governance_browser_repository_id}",
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
