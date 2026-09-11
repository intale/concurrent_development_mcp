# frozen_string_literal: true

module ProjectCoordinationGraphqlSpec
  RSpec.describe "GraphQL project coordination", :read_model do
    let(:scope) { "project:graphql-coordination" }
    let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000031" }
    let(:member_repository_id) { "018f0f4d-4e45-7abc-8def-000000000032" }
    let(:unrelated_repository_id) { "018f0f4d-4e45-7abc-8def-000000000039" }
    let(:project_ref) { Coordinator::Read::Web::ProjectReference.new.encode(scope:) }

    CHANGE_SETS_QUERY = <<~GRAPHQL.freeze
      query ChangeSets(
        $projectRef: ID!
        $first: Int
        $after: String
        $status: CoordinationChangeSetStatus
      ) {
        projectChangeSets(projectRef: $projectRef, first: $first, after: $after, status: $status) {
          nodes { id goal domainStatus workItemCount runningWorkItemCount openWorkItemCount }
          pageInfo { endCursor hasNextPage }
        }
      }
    GRAPHQL
    WORK_ITEMS_QUERY = <<~GRAPHQL.freeze
      query WorkItems(
        $projectRef: ID!
        $first: Int
        $after: String
        $agentId: String
        $changeSetId: ID
        $statuses: [CoordinationPresentationStatus!]
        $sort: WorkItemSort
      ) {
        projectWorkItems(
          projectRef: $projectRef
          first: $first
          after: $after
          agentId: $agentId
          changeSetId: $changeSetId
          presentationStatuses: $statuses
          sort: $sort
        ) {
          nodes { id goal presentationStatus activeAgentId activeAttemptId attemptStatus }
          pageInfo { endCursor hasNextPage }
        }
      }
    GRAPHQL
    WORK_ITEM_QUERY = <<~GRAPHQL.freeze
      query WorkItem($projectRef: ID!, $workItemId: ID!) {
        projectWorkItem(projectRef: $projectRef, workItemId: $workItemId) {
          workItem { id goal presentationStatus activeAgentId }
          attempt { id agentId status baseSnapshots { repositoryId objectFormat commitOid } }
          checkpoint { id checkpointKind headCommitOid evidenceStatus }
        }
      }
    GRAPHQL
    DEPENDENCIES_QUERY = <<~GRAPHQL.freeze
      query Dependencies($projectRef: ID!, $blocking: Boolean) {
        projectDependencies(projectRef: $projectRef, first: 20, blocking: $blocking) {
          nodes { id producerWorkItemId consumerWorkItemId blocking requiredOutput { kind key } }
        }
      }
    GRAPHQL
    DEPENDENCY_QUERY = <<~GRAPHQL.freeze
      query Dependency($projectRef: ID!, $dependencyId: ID!) {
        projectDependency(projectRef: $projectRef, dependencyId: $dependencyId) {
          id
          producerWorkItemId
          consumerWorkItemId
          blocking
          requiredOutput { kind key }
        }
      }
    GRAPHQL

    before do
      create(:coordinator_read_repository, repository_id:, repository_key: "coordination-primary", scope:)
      create(
        :coordinator_read_repository,
        repository_id: member_repository_id,
        repository_key: "coordination-member",
        scope:
      )
      create(
        :coordinator_read_repository,
        repository_id: unrelated_repository_id,
        repository_key: "coordination-unrelated",
        scope: "project:unrelated"
      )
      @project_context = create_context(
        change_set_id: "CS-project",
        work_items: [
          work_item("W-100", repository_id:, status: "acquired", attempt_id: "A-running"),
          work_item("W-300", repository_id: member_repository_id, status: "ready"),
          work_item("W-producer", repository_id:, status: "ready"),
          work_item("W-consumer", repository_id:, status: "planned")
        ],
        dependencies: [
          {
            "dependency_id" => "D-blocking",
            "producer_work_item_id" => "W-producer",
            "consumer_work_item_id" => "W-consumer",
            "dependency_kind" => "requires_contract",
            "required_output" => { "kind" => "contract", "key" => "coordination-ui-v1" },
            "source_event" => nil,
            "declared_at" => "2026-09-01T12:00:00.000000Z",
            "satisfied_at" => nil
          }
        ]
      )
      create_context(
        change_set_id: "CS-unrelated",
        work_items: [ work_item("W-unrelated", repository_id: unrelated_repository_id, status: "ready") ]
      )
      create(
        :coordinator_read_attempt_history,
        attempt_id: "A-running",
        change_set_id: "CS-project",
        work_item_id: "W-100",
        agent_id: "luna-one",
        status: "started",
        base_snapshots: [
          { "repository_id" => repository_id, "object_format" => "sha1", "commit_oid" => "a" * 40 }
        ],
        started_at_domain: Time.utc(2026, 9, 1, 12, 4),
        created_at: Time.utc(2026, 9, 1, 12, 4),
        updated_at: Time.utc(2026, 9, 1, 12, 4)
      )
      create(
        :coordinator_read_candidate,
        candidate_id: "CAND-running",
        change_set_id: "CS-project",
        work_item_id: "W-100",
        attempt_id: "A-running",
        agent_id: "luna-one",
        repository_id:,
        checkpoint_kind: "intermediate"
      )
    end

    it "aggregates ChangeSets and WorkItems across exact Project members" do
      change_sets = execute(CHANGE_SETS_QUERY, projectRef: project_ref, first: 20)
        .dig("data", "projectChangeSets", "nodes")
      work_items = execute(WORK_ITEMS_QUERY, projectRef: project_ref, first: 20, sort: "UPDATED_AT_ASC")
        .dig("data", "projectWorkItems", "nodes")

      expect(change_sets.sole).to include(
        "id" => "CS-project",
        "workItemCount" => 4,
        "runningWorkItemCount" => 1,
        "openWorkItemCount" => 3
      )
      expect(work_items.map { _1.fetch("id") }).to contain_exactly("W-100", "W-300", "W-producer", "W-consumer")
      expect(work_items.find { _1.fetch("id") == "W-100" }).to include(
        "presentationStatus" => "RUNNING",
        "activeAgentId" => "luna-one",
        "activeAttemptId" => "A-running",
        "attemptStatus" => "started"
      )
    end

    it "filters ChangeSets by exact lifecycle status and binds continuation to that filter" do
      create_context(
        change_set_id: "CS-completed",
        change_set_status: "completed",
        updated_at: Time.utc(2026, 9, 1, 12, 10),
        work_items: [ work_item("W-completed", repository_id:, status: "completed", change_set_id: "CS-completed") ]
      )
      create_context(
        change_set_id: "CS-active-newer",
        change_set_status: "active",
        updated_at: Time.utc(2026, 9, 1, 12, 11),
        work_items: [ work_item("W-active-newer", repository_id:, status: "ready", change_set_id: "CS-active-newer") ]
      )

      active = execute(
        CHANGE_SETS_QUERY,
        projectRef: project_ref,
        first: 1,
        status: "ACTIVE"
      ).dig("data", "projectChangeSets")
      completed = execute(
        CHANGE_SETS_QUERY,
        projectRef: project_ref,
        first: 20,
        status: "COMPLETED"
      ).dig("data", "projectChangeSets", "nodes")
      mismatched = execute(
        CHANGE_SETS_QUERY,
        projectRef: project_ref,
        first: 1,
        after: active.dig("pageInfo", "endCursor"),
        status: "COMPLETED"
      )

      expect(active.dig("nodes", 0, "id")).to eq("CS-active-newer")
      expect(active.dig("pageInfo", "hasNextPage")).to be(true)
      expect(completed.map { _1.fetch("id") }).to eq([ "CS-completed" ])
      expect(mismatched.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
    end

    it "returns a project-bound WorkItem with its latest Attempt and checkpoint" do
      detail = execute(WORK_ITEM_QUERY, projectRef: project_ref, workItemId: "W-100")
        .dig("data", "projectWorkItem")

      expect(detail.fetch("attempt")).to include(
        "id" => "A-running",
        "agentId" => "luna-one",
        "status" => "started"
      )
      expect(detail.dig("attempt", "baseSnapshots").sole).to include(
        "repositoryId" => repository_id,
        "objectFormat" => "sha1"
      )
      expect(detail.fetch("checkpoint")).to include(
        "id" => "CAND-running",
        "checkpointKind" => "intermediate"
      )
      unrelated = execute(WORK_ITEM_QUERY, projectRef: project_ref, workItemId: "W-unrelated")
      expect(unrelated.dig("data", "projectWorkItem")).to be_nil
    end

    it "exposes blocking dependency meaning and validates detail membership" do
      dependencies = execute(DEPENDENCIES_QUERY, projectRef: project_ref, blocking: true)
        .dig("data", "projectDependencies", "nodes")
      detail = execute(DEPENDENCY_QUERY, projectRef: project_ref, dependencyId: "D-blocking")
        .dig("data", "projectDependency")

      expect(dependencies.map { _1.fetch("id") }).to eq([ "D-blocking" ])
      expect(detail).to include(
        "producerWorkItemId" => "W-producer",
        "consumerWorkItemId" => "W-consumer",
        "blocking" => true,
        "requiredOutput" => { "kind" => "contract", "key" => "coordination-ui-v1" }
      )
    end

    it "uses stable keyset continuation when another projected row appears" do
      create_context(
        change_set_id: "CS-page",
        updated_at: Time.utc(2026, 8, 31, 10),
        work_items: [ work_item("W-page-100", repository_id:, status: "ready", change_set_id: "CS-page") ]
      )
      first_page = execute(
        WORK_ITEMS_QUERY,
        projectRef: project_ref,
        first: 1,
        sort: "UPDATED_AT_ASC"
      ).dig("data", "projectWorkItems")
      create_context(
        change_set_id: "CS-page-new",
        updated_at: Time.utc(2026, 8, 31, 11),
        work_items: [
          work_item("W-page-200", repository_id:, status: "ready", change_set_id: "CS-page-new")
        ]
      )
      second_page = execute(
        WORK_ITEMS_QUERY,
        projectRef: project_ref,
        first: 1,
        after: first_page.dig("pageInfo", "endCursor"),
        sort: "UPDATED_AT_ASC"
      ).dig("data", "projectWorkItems")

      expect(first_page.dig("nodes", 0, "id")).to eq("W-page-100")
      expect(second_page.dig("nodes", 0, "id")).to eq("W-page-200")
    end

    it "continues status and latest-activity ordering with the matching tuple key" do
      expectations = {
        "STATUS_ASC" => [ "W-consumer", "W-300" ],
        "LATEST_ACTIVITY_DESC" => [ "W-100", "W-300" ]
      }

      expectations.each do |sort, expected_ids|
        first_page = execute(
          WORK_ITEMS_QUERY,
          projectRef: project_ref,
          first: 1,
          sort:
        ).dig("data", "projectWorkItems")
        second_page = execute(
          WORK_ITEMS_QUERY,
          projectRef: project_ref,
          first: 1,
          after: first_page.dig("pageInfo", "endCursor"),
          sort:
        ).dig("data", "projectWorkItems")

        expect([ first_page.dig("nodes", 0, "id"), second_page.dig("nodes", 0, "id") ]).to eq(expected_ids)
      end
    end

    it "rejects a continuation cursor under changed filters" do
      first_page = execute(
        WORK_ITEMS_QUERY,
        projectRef: project_ref,
        first: 1,
        sort: "UPDATED_AT_ASC"
      ).dig("data", "projectWorkItems")
      payload = execute(
        WORK_ITEMS_QUERY,
        projectRef: project_ref,
        first: 1,
        after: first_page.dig("pageInfo", "endCursor"),
        statuses: [ "READY" ],
        sort: "UPDATED_AT_ASC"
      )

      expect(payload.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
    end

    it "maps a structurally malformed continuation cursor to a typed error" do
      cursor = Base64.urlsafe_encode64(JSON.generate([]), padding: false)
      payload = execute(
        WORK_ITEMS_QUERY,
        projectRef: project_ref,
        first: 1,
        after: cursor,
        sort: "UPDATED_AT_ASC"
      )

      expect(payload.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
    end

    it "maps malformed Project references to a typed error" do
      payload = execute(CHANGE_SETS_QUERY, projectRef: "not-a-project-reference", first: 20)

      expect(payload.dig("errors", 0, "extensions", "code")).to eq("INVALID_PROJECT_REFERENCE")
    end

    def create_context(
      change_set_id:,
      work_items:,
      dependencies: [],
      change_set_status: "active",
      updated_at: Time.utc(2026, 9, 1, 12)
    )
      template = build(
        :coordinator_read_coord_context,
        change_set_id:,
        repository_id: work_items.first.fetch("repository_id"),
        work_item_id: work_items.first.fetch("work_item_id")
      )
      document = template.document.deep_dup
      document.fetch("change_set")["goal"] = "Coordinate #{change_set_id}"
      document.fetch("change_set")["status"] = change_set_status
      document["work_items"] = work_items
      document["work_item_ids"] = work_items.map { _1.fetch("work_item_id") }
      document["dependencies"] = dependencies
      document["attempts"] = []
      create(:coordinator_read_coord_context, change_set_id:, document:, created_at: updated_at, updated_at:)
    end

    def work_item(work_item_id, repository_id:, status:, attempt_id: nil, change_set_id: nil)
      timestamp = "2026-09-01T12:00:00.000000Z"
      {
        "work_item_id" => work_item_id,
        "change_set_id" => change_set_id || (work_item_id == "W-unrelated" ? "CS-unrelated" : "CS-project"),
        "repository_id" => repository_id,
        "goal" => "Coordinate #{work_item_id}",
        "acceptance_criteria" => [ "#{work_item_id} remains inspectable" ],
        "competitive_mode" => false,
        "status" => status,
        "active_attempt_id" => attempt_id,
        "active_agent_id" => attempt_id && "embedded-agent",
        "selected_candidate_id" => nil,
        "selected_candidate_event" => nil,
        "produced_outputs" => [],
        "created_at" => timestamp,
        "made_ready_at" => status == "planned" ? nil : timestamp,
        "acquired_at" => attempt_id && timestamp,
        "selected_at" => nil,
        "completed_at" => status == "completed" ? timestamp : nil
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
