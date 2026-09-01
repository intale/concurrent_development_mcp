# frozen_string_literal: true

module ProjectDeliveryGraphqlSpec
  RSpec.describe "GraphQL project delivery", :read_model do
    CANDIDATES_QUERY = <<~GRAPHQL.freeze
      query Candidates(
        $projectRef: ID!
        $first: Int
        $sort: DeliverySort
        $changeSetId: ID
        $checkpointKind: CandidateCheckpointKind
        $after: String
      ) {
        projectCandidateCheckpoints(
          projectRef: $projectRef
          first: $first
          sort: $sort
          changeSetId: $changeSetId
          checkpointKind: $checkpointKind
          after: $after
        ) {
          nodes { id repositoryId changeSetId checkpointKind headCommitOid submittedAt }
          pageInfo { endCursor hasNextPage }
        }
      }
    GRAPHQL

    OBLIGATIONS_QUERY = <<~GRAPHQL.freeze
      query Obligations($projectRef: ID!, $status: VerificationObligationStatus) {
        projectVerificationObligations(projectRef: $projectRef, status: $status) {
          nodes { id status sourceRepositoryId targetRepositoryId evidenceCount }
          pageInfo { endCursor hasNextPage }
        }
      }
    GRAPHQL

    MERGES_QUERY = <<~GRAPHQL.freeze
      query Merges($projectRef: ID!) {
        projectMergeSnapshots(projectRef: $projectRef) {
          nodes { id repositoryId targetBranch candidateCount verificationStatus }
          pageInfo { endCursor hasNextPage }
        }
      }
    GRAPHQL

    RELEASES_QUERY = <<~GRAPHQL.freeze
      query Releases($projectRef: ID!, $status: ReleaseSetStatus) {
        projectReleaseSets(projectRef: $projectRef, status: $status) {
          nodes { id changeSetId repositoryIds memberCount status verificationStatus }
          pageInfo { endCursor hasNextPage }
        }
      }
    GRAPHQL

    CANDIDATE_QUERY = <<~GRAPHQL.freeze
      query Candidate($projectRef: ID!, $candidateId: ID!, $first: Int) {
        projectCandidateCheckpoint(projectRef: $projectRef, candidateId: $candidateId, first: $first) {
          checkpoint { id changeSetId manifestObserved }
          impactDirection
          impactSurfaceDigest
          impactRelationships {
            nodes { counterpart { id } relationshipKind reasons { kind matches } }
            pageInfo { endCursor hasNextPage }
          }
        }
      }
    GRAPHQL

    VERIFICATION_QUERY = <<~GRAPHQL.freeze
      query Verification($projectRef: ID!, $obligationId: ID!) {
        projectVerificationObligation(projectRef: $projectRef, obligationId: $obligationId) {
          obligation { id status claimantId evidenceCount missingEvidenceKinds }
          requiredEvidence
          reasons { kind matches }
          evidence {
            nodes { id evidenceKind conclusion resultDigest submittedAt globalPosition }
            pageInfo { endCursor hasNextPage }
          }
        }
      }
    GRAPHQL

    MERGE_QUERY = <<~GRAPHQL.freeze
      query Merge($projectRef: ID!, $mergeSnapshotId: ID!) {
        projectMergeSnapshot(projectRef: $projectRef, mergeSnapshotId: $mergeSnapshotId) {
          snapshot { id mergeCommitOid verificationStatus }
          candidates { id changeSetId workItemId attemptId }
          authorizations {
            nodes { id outcome reasonCount decisionDigest decidedAt }
            pageInfo { endCursor hasNextPage }
          }
        }
      }
    GRAPHQL

    RELEASE_QUERY = <<~GRAPHQL.freeze
      query Release($projectRef: ID!, $releaseSetId: ID!) {
        projectReleaseSet(projectRef: $projectRef, releaseSetId: $releaseSetId) {
          releaseSet { id changeSetId status repositoryIds }
          members { position repositoryId mergeSnapshotId candidateCount }
          integrations { repositoryId attemptId outcome failureCode }
          verificationAttemptCount
          activated
          compensationRequested
          completionOutcome
        }
      }
    GRAPHQL

    BATCHES_QUERY = <<~GRAPHQL.freeze
      query Batches($first: Int, $after: String, $status: OperationBatchStatus) {
        operationBatches(first: $first, after: $after, status: $status) {
          nodes { id targetTool status total succeeded rejected pending notRun createdAt }
          pageInfo { endCursor hasNextPage }
        }
      }
    GRAPHQL

    BATCH_QUERY = <<~GRAPHQL.freeze
      query Batch($batchId: ID!, $first: Int) {
        operationBatch(batchId: $batchId, first: $first) {
          batch { id status total }
          items {
            nodes { index targetTool commandId status outcomeStatus outcomeSummary outcomeCode finishedAt }
            pageInfo { endCursor hasNextPage }
          }
        }
      }
    GRAPHQL

    REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000081"
    MEMBER_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000082"
    OTHER_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000083"
    SCOPE = "project:graphql-delivery"
    CHANGE_SET_ID = "CS-graphql-delivery"

    before do
      create_project(REPOSITORY_ID, SCOPE, "GraphQL delivery")
      create_project(MEMBER_REPOSITORY_ID, SCOPE, "GraphQL delivery member")
      create_project(OTHER_REPOSITORY_ID, "project:graphql-delivery-other", "Other delivery")
    end

    it "serves focused Project collections with exact multi-Repository scope and bound cursors" do
      create(
        :coordinator_read_candidate,
        candidate_id: "CAN-graphql-new",
        change_set_id: CHANGE_SET_ID,
        repository_id: MEMBER_REPOSITORY_ID,
        submitted_global_position: 102
      )
      create(
        :coordinator_read_candidate,
        candidate_id: "CAN-graphql-old",
        change_set_id: CHANGE_SET_ID,
        repository_id: REPOSITORY_ID,
        head_commit_oid: "c" * 40,
        submitted_global_position: 101
      )
      create(
        :coordinator_read_candidate,
        candidate_id: "CAN-graphql-unrelated",
        change_set_id: CHANGE_SET_ID,
        repository_id: OTHER_REPOSITORY_ID,
        head_commit_oid: "d" * 40,
        submitted_global_position: 103
      )
      obligation = create(
        :coordinator_read_verification_obligation,
        obligation_id: "OBL-graphql-delivery",
        change_set_id: CHANGE_SET_ID,
        source_repository_id: MEMBER_REPOSITORY_ID,
        target_repository_id: OTHER_REPOSITORY_ID,
        event_global_position: 201
      )
      snapshot = create(
        :coordinator_read_merge_snapshot,
        merge_snapshot_id: "MS-graphql-delivery",
        repository_id: MEMBER_REPOSITORY_ID,
        registered_global_position: 301
      )
      release = create(
        :coordinator_read_release_set,
        release_set_id: "RS-graphql-delivery",
        change_set_id: CHANGE_SET_ID,
        repository_ids: [ MEMBER_REPOSITORY_ID, OTHER_REPOSITORY_ID ],
        prepared_global_position: 401
      )

      first = execute(
        CANDIDATES_QUERY,
        projectRef: project_ref,
        first: 1,
        sort: "NEWEST_FIRST",
        changeSetId: CHANGE_SET_ID,
        checkpointKind: "FINAL"
      )
      candidates = first.dig("data", "projectCandidateCheckpoints")
      cursor = candidates.dig("pageInfo", "endCursor")
      second = execute(
        CANDIDATES_QUERY,
        projectRef: project_ref,
        first: 1,
        sort: "NEWEST_FIRST",
        changeSetId: CHANGE_SET_ID,
        checkpointKind: "FINAL",
        after: cursor
      )
      mismatched = execute(
        CANDIDATES_QUERY,
        projectRef: other_project_ref,
        first: 1,
        sort: "NEWEST_FIRST",
        changeSetId: CHANGE_SET_ID,
        checkpointKind: "FINAL",
        after: cursor
      )
      obligations = execute(OBLIGATIONS_QUERY, projectRef: project_ref, status: "OPEN")
      merges = execute(MERGES_QUERY, projectRef: project_ref)
      releases = execute(RELEASES_QUERY, projectRef: project_ref, status: "PREPARED")

      expect(first.fetch("errors", [])).to be_empty, first.inspect
      expect(candidates.dig("nodes", 0, "id")).to eq("CAN-graphql-new")
      expect(cursor).not_to include("CAN-graphql-new")
      expect(second.dig("data", "projectCandidateCheckpoints", "nodes", 0, "id")).to eq(
        "CAN-graphql-old"
      )
      expect(mismatched.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
      expect(obligations.dig("data", "projectVerificationObligations", "nodes", 0, "id")).to eq(
        obligation.obligation_id
      )
      expect(merges.dig("data", "projectMergeSnapshots", "nodes", 0, "id")).to eq(
        snapshot.merge_snapshot_id
      )
      expect(releases.dig("data", "projectReleaseSets", "nodes", 0, "id")).to eq(
        release.release_set_id
      )
    end

    it "serves isolated typed details without normalized support rows" do
      candidate = create(
        :coordinator_read_candidate,
        :manifest_observed,
        candidate_id: "CAN-graphql-detail",
        change_set_id: CHANGE_SET_ID,
        repository_id: MEMBER_REPOSITORY_ID,
        submitted_global_position: 110
      )
      counterpart = create(
        :coordinator_read_candidate,
        :manifest_observed,
        candidate_id: "CAN-graphql-counterpart",
        change_set_id: CHANGE_SET_ID,
        repository_id: MEMBER_REPOSITORY_ID,
        head_commit_oid: "c" * 40,
        submitted_global_position: 111
      )
      [ candidate, counterpart ].each do |checkpoint|
        create(
          :coordinator_read_candidate_changed_resource,
          candidate_id: checkpoint.candidate_id,
          change_set_id: CHANGE_SET_ID,
          repository_id: MEMBER_REPOSITORY_ID,
          path: "lib/shared.rb"
        )
      end
      obligation = create(
        :coordinator_read_verification_obligation,
        obligation_id: "OBL-graphql-detail",
        change_set_id: CHANGE_SET_ID,
        source_repository_id: MEMBER_REPOSITORY_ID,
        target_repository_id: OTHER_REPOSITORY_ID,
        event_global_position: 210
      )
      evidence = create(
        :coordinator_read_verification_obligation_evidence_item,
        obligation_id: obligation.obligation_id,
        event_global_position: 211
      )
      snapshot = create(
        :coordinator_read_merge_snapshot,
        merge_snapshot_id: "MS-graphql-detail",
        repository_id: MEMBER_REPOSITORY_ID,
        registered_global_position: 310
      )
      authorization = create(
        :coordinator_read_merge_authorization,
        merge_snapshot_id: snapshot.merge_snapshot_id,
        source_global_position: 311
      )
      release = create(
        :coordinator_read_release_set,
        release_set_id: "RS-graphql-detail",
        change_set_id: CHANGE_SET_ID,
        repository_ids: [ REPOSITORY_ID, MEMBER_REPOSITORY_ID ]
      )

      candidate_result = execute(
        CANDIDATE_QUERY,
        projectRef: project_ref,
        candidateId: candidate.candidate_id,
        first: 20
      ).dig("data", "projectCandidateCheckpoint")
      verification_result = execute(
        VERIFICATION_QUERY,
        projectRef: project_ref,
        obligationId: obligation.obligation_id
      ).dig("data", "projectVerificationObligation")
      merge_result = execute(
        MERGE_QUERY,
        projectRef: project_ref,
        mergeSnapshotId: snapshot.merge_snapshot_id
      ).dig("data", "projectMergeSnapshot")
      release_result = execute(
        RELEASE_QUERY,
        projectRef: project_ref,
        releaseSetId: release.release_set_id
      ).dig("data", "projectReleaseSet")

      expect(candidate_result.dig("impactRelationships", "nodes", 0, "counterpart", "id")).to eq(
        counterpart.candidate_id
      )
      expect(verification_result.dig("evidence", "nodes", 0, "id")).to eq(evidence.evidence_id)
      expect(verification_result.dig("reasons", 0, "kind")).to eq("semantic_key_match")
      expect(merge_result.dig("authorizations", "nodes", 0, "id")).to eq(
        authorization.authorization_id
      )
      expect(release_result.fetch("members").map { _1.fetch("repositoryId") }).to eq(
        [ REPOSITORY_ID, MEMBER_REPOSITORY_ID ]
      )
      expect(execute(CANDIDATE_QUERY, projectRef: other_project_ref, candidateId: candidate.candidate_id)
        .dig("data", "projectCandidateCheckpoint")).to be_nil
    end

    it "keeps operation batches global and binds their cursors to exact filters" do
      batch = create(
        :coordinator_read_operation_batch,
        batch_id: "018f0f4d-4e45-7abc-8def-000000000091",
        created_global_position: 501
      )
      item = create(
        :coordinator_read_operation_batch_item,
        operation_batch: batch,
        item_index: 0,
        command_id: "graphql-batch-item"
      )
      create(
        :coordinator_read_operation_batch_outcome,
        operation_batch: batch,
        item_index: 0,
        command_id: item.command_id,
        outcome_global_position: 502
      )
      create(
        :coordinator_read_operation_batch,
        batch_id: "018f0f4d-4e45-7abc-8def-000000000092",
        created_global_position: 503
      )

      page = execute(BATCHES_QUERY, first: 1)
      cursor = page.dig("data", "operationBatches", "pageInfo", "endCursor")
      mismatched = execute(BATCHES_QUERY, first: 1, after: cursor, status: "COMPLETED_WITH_ERRORS")
      detail = execute(BATCH_QUERY, batchId: batch.batch_id, first: 20)

      expect(page.dig("data", "operationBatches", "nodes").length).to eq(1)
      expect(mismatched.dig("errors", 0, "extensions", "code")).to eq("INVALID_CURSOR")
      expect(detail.dig("data", "operationBatch", "items", "nodes", 0)).to include(
        "commandId" => "graphql-batch-item",
        "status" => "SUCCEEDED",
        "outcomeStatus" => "ok",
        "outcomeSummary" => "Skill revision published."
      )
    end

    def project_ref
      Coordinator::Read::Web::ProjectReference.new.encode(scope: SCOPE)
    end

    def other_project_ref
      Coordinator::Read::Web::ProjectReference.new.encode(scope: "project:graphql-delivery-other")
    end

    def create_project(repository_id, scope, name)
      create(
        :coordinator_read_repository,
        repository_id:,
        repository_key: "delivery-#{repository_id}",
        scope:,
        display_name: name
      )
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
