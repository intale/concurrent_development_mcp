# frozen_string_literal: true

module ProjectGovernanceGraphqlSpec
  RSpec.describe "GraphQL project governance", :read_model do
  CATALOG_QUERY = <<~GRAPHQL.freeze
    query ProjectGovernance(
      $repositoryId: ID!
      $first: Int
      $decisionTopicId: String
      $decisionPolicyStatus: DecisionPolicyStatus
      $afterDecision: String
      $guidanceSource: GuidanceSource
      $choiceStatus: AgentChoiceStatus
      $impactOutcome: AgentChoiceImpactOutcome
    ) {
      projectGovernance(
        repositoryId: $repositoryId
        first: $first
        decisionTopicId: $decisionTopicId
        decisionPolicyStatus: $decisionPolicyStatus
        afterDecision: $afterDecision
        guidanceSource: $guidanceSource
        choiceStatus: $choiceStatus
        impactOutcome: $impactOutcome
      ) {
        project { id name scope }
        decisions {
          nodes {
            id topicId policyStatus statementKind effect modality
            scope { repositoryIds attemptId }
          }
          pageInfo { endCursor hasNextPage }
        }
        guidance {
          nodes { id conversationId text excerpt source policyStatus anchors { repositoryIds attemptId } }
          pageInfo { endCursor hasNextPage }
        }
        choices {
          nodes {
            id choiceType observationStatus reasonSummary
            selected { id summary }
            context { repositoryId attemptId }
          }
          pageInfo { endCursor hasNextPage }
        }
        impacts {
          nodes {
            assessmentId choiceId attemptId outcome reason policyVersion
            decisionId decisionChangeKind beforeStatus afterStatus beforeBasis afterBasis
            beforeReasonCodes afterReasonCodes assessedAt
          }
          pageInfo { endCursor hasNextPage }
        }
      }
    }
  GRAPHQL

  DECISION_QUERY = <<~GRAPHQL.freeze
    query ProjectDecision($repositoryId: ID!, $decisionId: ID!) {
      projectDecision(repositoryId: $repositoryId, decisionId: $decisionId) {
        project { id scope }
        membershipBases
        decision {
          id topicId policyStatus rationaleSummary correctionCount correctionSummary
          recordedAt currentAt currentBy { kind id }
          conditions { phases languages tags environments }
        }
      }
    }
  GRAPHQL

  GUIDANCE_QUERY = <<~GRAPHQL.freeze
    query ProjectGuidance(
      $repositoryId: ID!
      $messageId: ID!
      $interpretationsFirst: Int
      $interpretationsAfter: String
    ) {
      projectGuidance(
        repositoryId: $repositoryId
        messageId: $messageId
        interpretationsFirst: $interpretationsFirst
        interpretationsAfter: $interpretationsAfter
      ) {
        project { id }
        guidance { id text actor { kind id } }
        interpretations {
          nodes {
            id messageId lifecycleStatus policyStatus statementKind topicId effect modality
            sourceSpanText assessmentStatus assessmentReasons
            clarificationQuestions { field prompt options }
            value { schema name }
            actor { kind id }
          }
          pageInfo { endCursor hasNextPage }
        }
      }
    }
  GRAPHQL

  CHOICE_QUERY = <<~GRAPHQL.freeze
    query ProjectAgentChoice(
      $repositoryId: ID!
      $choiceId: ID!
      $impactsFirst: Int
      $impactsAfter: String
    ) {
      projectAgentChoice(
        repositoryId: $repositoryId
        choiceId: $choiceId
        impactsFirst: $impactsFirst
        impactsAfter: $impactsAfter
      ) {
        project { id }
        choice {
          id observationStatus acceptedAt acceptedBy { kind id }
          assessmentBasis assessmentDecisionIds assessmentWarnings
          invalidatedAt invalidationReason
        }
        impacts {
          nodes { assessmentId choiceId outcome decisionId afterStatus }
          pageInfo { endCursor hasNextPage }
        }
      }
    }
  GRAPHQL

  RECEIPTS_QUERY = <<~GRAPHQL.freeze
    query CommandReceipts($first: Int, $after: String, $toolName: String) {
      commandReceipts(first: $first, after: $after, toolName: $toolName) {
        nodes {
          commandId toolName status summary receipt completedAt warnings nextActionTools
          emittedEvents { id type streamContext streamName streamId streamRevision }
        }
        pageInfo { endCursor hasNextPage }
      }
    }
  GRAPHQL

  RECEIPT_QUERY = <<~GRAPHQL.freeze
    query CommandReceipt($commandId: ID!) {
      commandReceipt(commandId: $commandId) {
        commandId toolName status summary receipt completedAt warnings nextActionTools
        emittedEvents { id type streamId streamRevision }
      }
    }
  GRAPHQL

  REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000081"
  OTHER_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000082"
  CHANGE_SET_ID = "CS-graphql-governance"
  WORK_ITEM_ID = "W-graphql-governance"
  ATTEMPT_ID = "A-graphql-governance-history"
  IMPACT_ID = "choice-impact-v1:#{'1' * 64}"

  before do
    create_project(REPOSITORY_ID, "project:graphql-governance", "GraphQL governance")
    create_project(OTHER_REPOSITORY_ID, "project:other-governance", "Other governance")
    create_coordination_context
    create_decisions
    create_guidance
    create_choices
    create_receipts
  end

  it "serves typed, bounded governance facts for the exact project" do
    response = execute(
      CATALOG_QUERY,
      repositoryId: REPOSITORY_ID,
      first: 1,
      decisionTopicId: "testing.framework",
      decisionPolicyStatus: "RECORDED",
      guidanceSource: "AGENT_FORWARDED",
      choiceStatus: "ACCEPTED",
      impactOutcome: "INVALIDATED"
    )
    expect(response.fetch("errors", [])).to be_empty, response.inspect
    result = response.dig("data", "projectGovernance")

    expect(result.fetch("project")).to include(
      "id" => REPOSITORY_ID,
      "name" => "GraphQL governance"
    )
    expect(result.dig("decisions", "nodes", 0)).to include(
      "id" => "D-direct",
      "topicId" => "testing.framework",
      "policyStatus" => "RECORDED",
      "effect" => "prefer"
    )
    expect(result.dig("decisions", "nodes", 0, "scope", "repositoryIds")).to eq([ REPOSITORY_ID ])
    expect(result.dig("decisions", "pageInfo", "hasNextPage")).to be(true)
    expect(result.dig("guidance", "nodes", 0)).to include(
      "id" => "M-project-guidance",
      "source" => "AGENT_FORWARDED"
    )
    expect(result.dig("choices", "nodes", 0)).to include(
      "id" => "CHO-project",
      "choiceType" => "TESTING_FRAMEWORK",
      "observationStatus" => "ACCEPTED"
    )
    expect(result.dig("impacts", "nodes", 0)).to include(
      "assessmentId" => IMPACT_ID,
      "outcome" => "INVALIDATED",
      "afterStatus" => "blocked"
    )
  end

  it "uses unbounded Attempt history for Decision membership and exposes detail provenance" do
    response = execute(CATALOG_QUERY, repositoryId: REPOSITORY_ID, first: 1)
    expect(response.fetch("errors", [])).to be_empty, response.inspect
    first = response.dig("data", "projectGovernance", "decisions")
    cursor = first.dig("pageInfo", "endCursor")
    second = execute(
      CATALOG_QUERY,
      repositoryId: REPOSITORY_ID,
      first: 1,
      afterDecision: cursor
    ).dig("data", "projectGovernance", "decisions")
    detail = execute(
      DECISION_QUERY,
      repositoryId: REPOSITORY_ID,
      decisionId: "D-history"
    ).dig("data", "projectDecision")

    expect(cursor).not_to include("D-direct")
    expect(second.dig("nodes", 0, "id")).to eq("D-history")
    expect(detail.fetch("membershipBases")).to eq([ "attempt" ])
    expect(detail.dig("decision", "id")).to eq("D-history")
    expect(detail.dig("decision", "conditions", "languages")).to eq([ "ruby" ])
  end

  it "serves guidance interpretations, choice impacts, and global command receipts as typed facts" do
    guidance = execute(
      GUIDANCE_QUERY,
      repositoryId: REPOSITORY_ID,
      messageId: "M-project-guidance",
      interpretationsFirst: 20
    ).dig("data", "projectGuidance")
    choice = execute(
      CHOICE_QUERY,
      repositoryId: REPOSITORY_ID,
      choiceId: "CHO-project",
      impactsFirst: 20
    ).dig("data", "projectAgentChoice")
    receipts = execute(RECEIPTS_QUERY, first: 1).dig("data", "commandReceipts")
    receipt = execute(RECEIPT_QUERY, commandId: "cmd-a").dig("data", "commandReceipt")

    expect(guidance.dig("interpretations", "nodes", 0)).to include(
      "id" => "I-project-guidance",
      "assessmentStatus" => "accepted_for_activation",
      "topicId" => "testing.framework"
    )
    expect(choice.fetch("choice")).to include(
      "id" => "CHO-project",
      "observationStatus" => "ACCEPTED",
      "assessmentBasis" => "no_policy"
    )
    expect(choice.dig("impacts", "nodes", 0)).to include(
      "assessmentId" => IMPACT_ID,
      "decisionId" => "D-CHO-project"
    )
    expect(receipts.dig("nodes", 0)).to include(
      "commandId" => "cmd-a",
      "toolName" => "change_set_create",
      "status" => "OK"
    )
    expect(receipts.dig("pageInfo", "hasNextPage")).to be(true)
    expect(receipt).to include("commandId" => "cmd-a", "nextActionTools" => [])
    expect(receipt).not_to have_key("data")
  end

  it "binds opaque cursors to filters and isolates project-scoped details" do
    response = execute(CATALOG_QUERY, repositoryId: REPOSITORY_ID, first: 1)
    expect(response.fetch("errors", [])).to be_empty, response.inspect
    cursor = response.dig("data", "projectGovernance", "decisions", "pageInfo", "endCursor")
    mismatched = execute(
      CATALOG_QUERY,
      repositoryId: REPOSITORY_ID,
      first: 1,
      decisionPolicyStatus: "RECORDED",
      afterDecision: cursor
    )
    malformed = execute(CATALOG_QUERY, repositoryId: "not-a-uuid", first: 20)
    unbounded = execute(CATALOG_QUERY, repositoryId: REPOSITORY_ID, first: 51)
    outside = execute(
      DECISION_QUERY,
      repositoryId: OTHER_REPOSITORY_ID,
      decisionId: "D-direct"
    )

    expect(mismatched.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
    expect(malformed.dig("errors", 0, "extensions", "code")).to eq("INVALID_INPUT")
    expect(unbounded.dig("errors", 0, "extensions", "code")).to eq("INVALID_INPUT")
    expect(outside.dig("data", "projectDecision")).to be_nil
  end

  def create_project(repository_id, scope, name)
    create(
      :coordinator_read_repository,
      repository_id:,
      repository_key: "governance-#{repository_id}",
      scope:,
      display_name: name
    )
  end

  def create_coordination_context
    context = create(
      :coordinator_read_coord_context,
      change_set_id: CHANGE_SET_ID,
      work_item_id: WORK_ITEM_ID,
      repository_id: REPOSITORY_ID
    )
    context.update!(document: context.document.merge("attempts" => []))
    create(
      :coordinator_read_attempt_history,
      attempt_id: ATTEMPT_ID,
      change_set_id: CHANGE_SET_ID,
      work_item_id: WORK_ITEM_ID
    )
  end

  def create_decisions
    create(
      :coordinator_read_decision_definition,
      decision_id: "D-direct",
      repository_id: REPOSITORY_ID,
      topic_id: "testing.framework"
    )
    create(
      :coordinator_read_decision_definition,
      decision_id: "D-history",
      repository_id: nil,
      attempt_id: ATTEMPT_ID,
      topic_id: "testing.framework"
    )
    create(
      :coordinator_read_decision_definition,
      decision_id: "D-other",
      repository_id: OTHER_REPOSITORY_ID,
      topic_id: "testing.framework"
    )
  end

  def create_guidance
    create(
      :coordinator_read_user_utterance,
      message_id: "M-project-guidance",
      conversation_id: "C-project-guidance",
      text: "Use the approved testing boundary.",
      anchors: guidance_anchors(REPOSITORY_ID)
    )
    create(
      :coordinator_read_decision_interpretation,
      interpretation_id: "I-project-guidance",
      message_id: "M-project-guidance",
      stream_revision: 1
    )
    create(
      :coordinator_read_user_utterance,
      message_id: "M-other-guidance",
      conversation_id: "C-other-guidance",
      anchors: guidance_anchors(OTHER_REPOSITORY_ID)
    )
  end

  def create_choices
    create(
      :coordinator_read_agent_choice,
      :accepted,
      choice_id: "CHO-project",
      context: choice_context(REPOSITORY_ID, ATTEMPT_ID)
    )
    create(
      :coordinator_read_agent_choice,
      :accepted,
      choice_id: "CHO-other",
      context: choice_context(OTHER_REPOSITORY_ID, "A-other")
    )
    create(
      :coordinator_read_agent_choice_impact,
      assessment_id: IMPACT_ID,
      choice_id: "CHO-project",
      attempt_id: ATTEMPT_ID,
      event_global_position: 801
    )
  end

  def create_receipts
    create(:coordinator_read_command_receipt, command_id: "cmd-a", tool_name: "change_set_create")
    create(:coordinator_read_command_receipt, command_id: "cmd-b", tool_name: "work_item_create")
  end

  def guidance_anchors(repository_id)
    {
      "repository_ids" => [ repository_id ],
      "change_set_id" => nil,
      "work_item_id" => nil,
      "attempt_id" => nil
    }
  end

  def choice_context(repository_id, attempt_id)
    {
      "workspace_id" => nil,
      "repository_id" => repository_id,
      "change_set_id" => CHANGE_SET_ID,
      "work_item_id" => WORK_ITEM_ID,
      "attempt_id" => attempt_id,
      "phase" => "implementation",
      "language" => "ruby",
      "paths" => [ "app/models/order.rb" ],
      "environment" => "test",
      "agent_role" => "implementer"
    }
  end

  def execute(query, variables)
    graphql_session.post "/graphql", params: { query:, variables: }, as: :json
    expect(graphql_session.response.status).to eq(200), graphql_session.response.body
    graphql_session.response.parsed_body
  end

  def graphql_session
    @graphql_session ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host! "localhost"
    end
  end
  end
end
