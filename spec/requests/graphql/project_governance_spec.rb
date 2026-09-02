# frozen_string_literal: true

module ProjectGovernanceGraphqlSpec
  RSpec.describe "GraphQL project governance", :read_model do
    COLLECTIONS_QUERY = <<~GRAPHQL.freeze
      query ProjectGovernanceCollections(
        $projectRef: ID!
        $first: Int
        $afterDecision: String
        $decisionStatus: DecisionPolicyStatus
        $decisionTopic: String
        $guidanceSource: GuidanceSource
        $choiceType: AgentChoiceKind
        $choiceStatus: AgentChoiceStatus
        $impactOutcome: AgentChoiceImpactOutcome
      ) {
        projectDecisions(
          projectRef: $projectRef
          first: $first
          after: $afterDecision
          policyStatus: $decisionStatus
          topicId: $decisionTopic
        ) {
          nodes {
            id topicId policyStatus statementKind effect modality currentAt
            scope { repositoryIds attemptId }
            value { schema name items action }
          }
          pageInfo { endCursor hasNextPage }
        }
        projectGuidanceMessages(projectRef: $projectRef, first: $first, source: $guidanceSource) {
          nodes { id excerpt source policyStatus recordedAt actor { kind id } }
          pageInfo { endCursor hasNextPage }
        }
        projectAgentChoices(
          projectRef: $projectRef
          first: $first
          choiceType: $choiceType
          status: $choiceStatus
        ) {
          nodes {
            id choiceType observationStatus reasonSummary recordedAt
            selected { id summary }
            context { repositoryId workItemId attemptId }
          }
          pageInfo { endCursor hasNextPage }
        }
        projectDecisionImpacts(projectRef: $projectRef, first: $first, outcome: $impactOutcome) {
          nodes {
            assessmentId choiceId attemptId outcome reason policyVersion
            decisionId decisionChangeKind beforeStatus afterStatus assessedAt
          }
          pageInfo { endCursor hasNextPage }
        }
      }
    GRAPHQL

    DECISION_QUERY = <<~GRAPHQL.freeze
      query ProjectDecision($projectRef: ID!, $decisionId: ID!) {
        projectDecision(projectRef: $projectRef, decisionId: $decisionId) {
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
        $projectRef: ID!
        $messageId: ID!
        $interpretationsFirst: Int
        $interpretationsAfter: String
      ) {
        projectGuidance(
          projectRef: $projectRef
          messageId: $messageId
          interpretationsFirst: $interpretationsFirst
          interpretationsAfter: $interpretationsAfter
        ) {
          guidance { id text actor { kind id } }
          interpretations {
            nodes {
              id messageId lifecycleStatus topicId assessmentStatus assessmentReasons
              value { schema name }
            }
            pageInfo { endCursor hasNextPage }
          }
        }
      }
    GRAPHQL

    CHOICE_QUERY = <<~GRAPHQL.freeze
      query ProjectAgentChoice(
        $projectRef: ID!
        $choiceId: ID!
        $impactsFirst: Int
        $impactsAfter: String
      ) {
        projectAgentChoice(
          projectRef: $projectRef
          choiceId: $choiceId
          impactsFirst: $impactsFirst
          impactsAfter: $impactsAfter
        ) {
          choice {
            id observationStatus acceptedAt assessmentBasis assessmentDecisionIds
            invalidatedAt invalidationReason
          }
          impacts {
            nodes { assessmentId choiceId outcome decisionId afterStatus }
            pageInfo { endCursor hasNextPage }
          }
        }
      }
    GRAPHQL

    IMPACT_QUERY = <<~GRAPHQL.freeze
      query ProjectDecisionImpact($projectRef: ID!, $assessmentId: ID!) {
        projectDecisionImpact(projectRef: $projectRef, assessmentId: $assessmentId) {
          impact {
            assessmentId choiceId attemptId outcome reason decisionId decisionChangeKind
            beforeStatus beforeBasis beforeReasonCodes
            afterStatus afterBasis afterReasonCodes assessedAt
          }
        }
      }
    GRAPHQL

    ISOLATED_COLLECTION_QUERY = <<~GRAPHQL.freeze
      query IsolatedGovernanceCollections($projectRef: ID!, $guidanceAfter: String!) {
        projectDecisions(projectRef: $projectRef, first: 20) { nodes { id } }
        projectGuidanceMessages(projectRef: $projectRef, first: 20, after: $guidanceAfter) {
          nodes { id }
        }
      }
    GRAPHQL

    RECEIPT_ISOLATION_QUERY = <<~GRAPHQL.freeze
      query ReceiptIsolation($projectRef: ID!, $commandId: ID!) {
        projectDecisions(projectRef: $projectRef, first: 20) { nodes { id } }
        commandReceipt(commandId: $commandId) { commandId nextActionTools }
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
    MEMBER_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000083"
    OTHER_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000082"
    PROJECT_SCOPE = "project:graphql-governance"
    CHANGE_SET_ID = "CS-graphql-governance"
    WORK_ITEM_ID = "W-graphql-governance"
    ATTEMPT_ID = "A-graphql-governance-history"
    IMPACT_ID = "choice-impact-v1:#{'1' * 64}"

    before do
      create_project(REPOSITORY_ID, PROJECT_SCOPE)
      create_project(MEMBER_REPOSITORY_ID, PROJECT_SCOPE)
      create_project(OTHER_REPOSITORY_ID, "project:other-governance")
      create_coordination_context
      create_governance_facts
      create_receipt
    end

    it "serves independently bounded collections across the exact Project scope" do
      response = execute(
        COLLECTIONS_QUERY,
        projectRef: project_ref,
        first: 1,
        decisionTopic: "testing.framework",
        decisionStatus: "RECORDED",
        guidanceSource: "AGENT_FORWARDED",
        choiceType: "TESTING_FRAMEWORK",
        choiceStatus: "ACCEPTED",
        impactOutcome: "INVALIDATED"
      )
      expect(response.fetch("errors", [])).to be_empty, response.inspect

      expect(response.dig("data", "projectDecisions", "nodes", 0)).to include(
        "id" => "D-history",
        "topicId" => "testing.framework",
        "policyStatus" => "RECORDED"
      )
      expect(response.dig("data", "projectDecisions", "pageInfo", "hasNextPage")).to be(true)
      expect(response.dig("data", "projectGuidanceMessages", "nodes", 0)).to include(
        "id" => "M-project-guidance",
        "source" => "AGENT_FORWARDED"
      )
      expect(response.dig("data", "projectAgentChoices", "nodes", 0)).to include(
        "id" => "CHO-project",
        "observationStatus" => "ACCEPTED"
      )
      expect(response.dig("data", "projectDecisionImpacts", "nodes", 0)).to include(
        "assessmentId" => IMPACT_ID,
        "outcome" => "INVALIDATED"
      )
    end

    it "serves dedicated project-bound details for every substantial Governance fact" do
      decision = execute(DECISION_QUERY, projectRef: project_ref, decisionId: "D-history")
        .dig("data", "projectDecision")
      guidance = execute(
        GUIDANCE_QUERY,
        projectRef: project_ref,
        messageId: "M-project-guidance",
        interpretationsFirst: 20
      ).dig("data", "projectGuidance")
      choice = execute(
        CHOICE_QUERY,
        projectRef: project_ref,
        choiceId: "CHO-project",
        impactsFirst: 20
      ).dig("data", "projectAgentChoice")
      impact = execute(IMPACT_QUERY, projectRef: project_ref, assessmentId: IMPACT_ID)
        .dig("data", "projectDecisionImpact", "impact")

      expect(decision.fetch("membershipBases")).to eq([ "attempt" ])
      expect(decision.dig("decision", "conditions", "languages")).to eq([ "ruby" ])
      expect(guidance.dig("interpretations", "nodes", 0)).to include(
        "id" => "I-project-guidance",
        "assessmentStatus" => "accepted_for_activation"
      )
      expect(choice.fetch("choice")).to include(
        "id" => "CHO-project",
        "observationStatus" => "ACCEPTED"
      )
      expect(choice.dig("impacts", "nodes", 0, "assessmentId")).to eq(IMPACT_ID)
      expect(impact).to include(
        "assessmentId" => IMPACT_ID,
        "choiceId" => "CHO-project",
        "afterStatus" => "blocked"
      )
    end

    it "binds cursors to Project and filters and isolates one collection failure" do
      first = execute(COLLECTIONS_QUERY, projectRef: project_ref, first: 1)
      cursor = first.dig("data", "projectDecisions", "pageInfo", "endCursor")
      mismatched = execute(
        COLLECTIONS_QUERY,
        projectRef: project_ref,
        first: 1,
        decisionStatus: "RECORDED",
        afterDecision: cursor
      )
      isolated = execute(
        ISOLATED_COLLECTION_QUERY,
        projectRef: project_ref,
        guidanceAfter: "not-a-cursor"
      )
      malformed = execute(COLLECTIONS_QUERY, projectRef: "not-a-reference", first: 20)
      outside = execute(
        DECISION_QUERY,
        projectRef: other_project_ref,
        decisionId: "D-history"
      )

      expect(cursor).not_to include("D-history")
      expect(mismatched.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
      expect(isolated.dig("data", "projectDecisions", "nodes")).not_to be_empty
      expect(isolated.dig("data", "projectGuidanceMessages")).to be_nil
      expect(isolated.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
      expect(malformed.dig("errors", 0, "extensions", "code")).to eq("INVALID_PROJECT_REFERENCE")
      expect(outside.dig("data", "projectDecision")).to be_nil
    end

    it "keeps malformed global receipts isolated from available Project Governance" do
      receipt = Coordinator::Read::CommandReceipt.find("cmd-a")
      receipt.update!(
        completion: receipt.completion.merge(
          "next_actions" => [ { "tool" => "not a tool", "arguments" => {} } ]
        )
      )

      failed = execute(RECEIPT_ISOLATION_QUERY, projectRef: project_ref, commandId: "cmd-a")
      expect(failed.dig("data", "projectDecisions", "nodes")).not_to be_empty
      expect(failed.dig("data", "commandReceipt")).to be_nil
      expect(failed.dig("errors", 0, "extensions")).to include(
        "code" => "READ_MODEL_INVALID",
        "retryable" => true
      )

      receipt.update!(completion: valid_completion(receipt))
      retried = execute(RECEIPT_QUERY, commandId: "cmd-a")
      expect(retried.fetch("errors", [])).to be_empty
      expect(retried.dig("data", "commandReceipt", "nextActionTools"))
        .to eq([ "development_artifact_get" ])
      expect(retried.dig("data", "commandReceipt")).not_to have_key("data")
    end

    def project_ref
      @project_ref ||= Coordinator::Read::Web::ProjectReference.new.encode(scope: PROJECT_SCOPE)
    end

    def other_project_ref
      @other_project_ref ||= Coordinator::Read::Web::ProjectReference.new.encode(
        scope: "project:other-governance"
      )
    end

    def create_project(repository_id, scope)
      create(
        :coordinator_read_repository,
        repository_id:,
        repository_key: "governance-#{repository_id}",
        scope:,
        display_name: "GraphQL governance"
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

    def create_governance_facts
      create(
        :coordinator_read_decision_definition,
        decision_id: "D-member",
        repository_id: MEMBER_REPOSITORY_ID,
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
      create(
        :coordinator_read_user_utterance,
        message_id: "M-project-guidance",
        conversation_id: "C-project-guidance",
        text: "Use the approved testing boundary.",
        anchors: guidance_anchors(MEMBER_REPOSITORY_ID)
      )
      create(
        :coordinator_read_decision_interpretation,
        interpretation_id: "I-project-guidance",
        message_id: "M-project-guidance",
        stream_revision: 1
      )
      create(
        :coordinator_read_agent_choice,
        :accepted,
        choice_id: "CHO-project",
        context: choice_context(MEMBER_REPOSITORY_ID, ATTEMPT_ID)
      )
      create(
        :coordinator_read_agent_choice_impact,
        assessment_id: IMPACT_ID,
        choice_id: "CHO-project",
        attempt_id: ATTEMPT_ID,
        event_global_position: 801
      )
    end

    def create_receipt
      receipt = create(
        :coordinator_read_command_receipt,
        command_id: "cmd-a",
        tool_name: "change_set_create"
      )
      receipt.update!(completion: valid_completion(receipt))
    end

    def valid_completion(receipt)
      receipt.completion.merge(
        "next_actions" => [
          {
            "tool" => "development_artifact_get",
            "arguments" => { "artifact_id" => "018f0f4d-4e45-7abc-8def-000000000211" }
          }
        ]
      )
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
