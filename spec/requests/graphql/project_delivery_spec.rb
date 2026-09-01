# frozen_string_literal: true

module ProjectDeliveryGraphqlSpec
  RSpec.describe "GraphQL project delivery", :read_model do
  CATALOG_QUERY = <<~GRAPHQL.freeze
    query ProjectDelivery(
      $repositoryId: ID!
      $first: Int
      $sort: DeliverySort
      $candidateChangeSetId: ID
      $candidateCheckpointKind: CandidateCheckpointKind
      $obligationStatus: VerificationObligationStatus
      $releaseStatus: ReleaseSetStatus
      $afterCandidate: String
    ) {
      projectDelivery(
        repositoryId: $repositoryId
        first: $first
        sort: $sort
        candidateChangeSetId: $candidateChangeSetId
        candidateCheckpointKind: $candidateCheckpointKind
        obligationStatus: $obligationStatus
        releaseStatus: $releaseStatus
        afterCandidate: $afterCandidate
      ) {
        project { id name scope }
        candidates {
          nodes { id changeSetId workItemId attemptId checkpointKind headCommitOid manifestObserved submittedAt }
          pageInfo { endCursor hasNextPage }
        }
        obligations {
          nodes { id changeSetId status sourceRepositoryId targetRepositoryId evidenceCount }
          pageInfo { endCursor hasNextPage }
        }
        mergeSnapshots {
          nodes { id repositoryId targetBranch candidateCount verificationStatus producedAt }
          pageInfo { endCursor hasNextPage }
        }
        releaseSets {
          nodes { id changeSetId repositoryIds memberCount status verificationStatus preparedAt }
          pageInfo { endCursor hasNextPage }
        }
      }
    }
  GRAPHQL

  CANDIDATE_QUERY = <<~GRAPHQL.freeze
    query Candidate($repositoryId: ID!, $candidateId: ID!, $first: Int) {
      projectCandidateCheckpoint(repositoryId: $repositoryId, candidateId: $candidateId, first: $first) {
        project { id }
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
    query Verification($repositoryId: ID!, $obligationId: ID!) {
      projectVerificationObligation(repositoryId: $repositoryId, obligationId: $obligationId) {
        project { id }
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
    query Merge($repositoryId: ID!, $mergeSnapshotId: ID!) {
      projectMergeSnapshot(repositoryId: $repositoryId, mergeSnapshotId: $mergeSnapshotId) {
        project { id }
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
    query Release($repositoryId: ID!, $releaseSetId: ID!) {
      projectReleaseSet(repositoryId: $repositoryId, releaseSetId: $releaseSetId) {
        project { id }
        releaseSet { id changeSetId status repositoryIds }
        members { position repositoryId mergeSnapshotId candidateCount }
        integrations { repositoryId attemptId outcome failureCode }
        verificationAttemptCount activated compensationRequested completionOutcome
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
  OTHER_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000082"
  CHANGE_SET_ID = "CS-graphql-delivery"

  before do
    create_project(REPOSITORY_ID, "project:graphql-delivery", "GraphQL delivery")
    create_project(OTHER_REPOSITORY_ID, "project:graphql-delivery-other", "Other delivery")
  end

  it "serves filtered project delivery collections and opaque stable cursors" do
    create(
      :coordinator_read_candidate,
      candidate_id: "CAN-graphql-new",
      change_set_id: CHANGE_SET_ID,
      repository_id: REPOSITORY_ID,
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
      :coordinator_read_verification_obligation,
      obligation_id: "OBL-graphql-delivery",
      change_set_id: CHANGE_SET_ID,
      source_repository_id: REPOSITORY_ID,
      target_repository_id: OTHER_REPOSITORY_ID,
      event_global_position: 201
    )
    create(
      :coordinator_read_merge_snapshot,
      merge_snapshot_id: "MS-graphql-delivery",
      repository_id: REPOSITORY_ID,
      registered_global_position: 301
    )
    create(
      :coordinator_read_release_set,
      release_set_id: "RS-graphql-delivery",
      change_set_id: CHANGE_SET_ID,
      repository_ids: [ REPOSITORY_ID, OTHER_REPOSITORY_ID ],
      prepared_global_position: 401
    )

    first = execute(
      CATALOG_QUERY,
      repositoryId: REPOSITORY_ID,
      first: 1,
      sort: "NEWEST_FIRST",
      candidateChangeSetId: CHANGE_SET_ID,
      candidateCheckpointKind: "FINAL",
      obligationStatus: "OPEN",
      releaseStatus: "PREPARED"
    )
    delivery = first.dig("data", "projectDelivery")
    cursor = delivery.dig("candidates", "pageInfo", "endCursor")
    second = execute(
      CATALOG_QUERY,
      repositoryId: REPOSITORY_ID,
      first: 1,
      sort: "NEWEST_FIRST",
      candidateChangeSetId: CHANGE_SET_ID,
      candidateCheckpointKind: "FINAL",
      obligationStatus: "OPEN",
      releaseStatus: "PREPARED",
      afterCandidate: cursor
    )

    expect(first.fetch("errors", [])).to be_empty, first.inspect
    expect(delivery.fetch("project")).to include("id" => REPOSITORY_ID, "name" => "GraphQL delivery")
    expect(delivery.dig("candidates", "nodes", 0, "id")).to eq("CAN-graphql-new")
    expect(cursor).not_to include("CAN-graphql-new")
    expect(second.dig("data", "projectDelivery", "candidates", "nodes", 0, "id")).to eq(
      "CAN-graphql-old"
    )
    expect(delivery.dig("obligations", "nodes", 0, "id")).to eq("OBL-graphql-delivery")
    expect(delivery.dig("mergeSnapshots", "nodes", 0, "id")).to eq("MS-graphql-delivery")
    expect(delivery.dig("releaseSets", "nodes", 0, "repositoryIds")).to eq(
      [ REPOSITORY_ID, OTHER_REPOSITORY_ID ]
    )
  end

  it "serves typed project details without exposing normalized support rows" do
    candidate = create(
      :coordinator_read_candidate,
      :manifest_observed,
      candidate_id: "CAN-graphql-detail",
      change_set_id: CHANGE_SET_ID,
      repository_id: REPOSITORY_ID,
      submitted_global_position: 110
    )
    counterpart = create(
      :coordinator_read_candidate,
      :manifest_observed,
      candidate_id: "CAN-graphql-counterpart",
      change_set_id: CHANGE_SET_ID,
      repository_id: REPOSITORY_ID,
      head_commit_oid: "c" * 40,
      submitted_global_position: 111
    )
    [ candidate, counterpart ].each do |checkpoint|
      create(
        :coordinator_read_candidate_changed_resource,
        candidate_id: checkpoint.candidate_id,
        change_set_id: CHANGE_SET_ID,
        repository_id: REPOSITORY_ID,
        path: "lib/shared.rb"
      )
    end
    obligation = create(
      :coordinator_read_verification_obligation,
      obligation_id: "OBL-graphql-detail",
      change_set_id: CHANGE_SET_ID,
      source_repository_id: REPOSITORY_ID,
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
      repository_id: REPOSITORY_ID,
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
      repository_ids: [ REPOSITORY_ID, OTHER_REPOSITORY_ID ]
    )

    candidate_result = execute(
      CANDIDATE_QUERY,
      repositoryId: REPOSITORY_ID,
      candidateId: candidate.candidate_id,
      first: 20
    ).dig("data", "projectCandidateCheckpoint")
    verification_result = execute(
      VERIFICATION_QUERY,
      repositoryId: REPOSITORY_ID,
      obligationId: obligation.obligation_id
    ).dig("data", "projectVerificationObligation")
    merge_result = execute(
      MERGE_QUERY,
      repositoryId: REPOSITORY_ID,
      mergeSnapshotId: snapshot.merge_snapshot_id
    ).dig("data", "projectMergeSnapshot")
    release_result = execute(
      RELEASE_QUERY,
      repositoryId: REPOSITORY_ID,
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
      [ REPOSITORY_ID, OTHER_REPOSITORY_ID ]
    )
  end

  it "keeps operation batches global and binds cursors to exact filters" do
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
