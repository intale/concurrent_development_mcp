# frozen_string_literal: true

DELIVERY_CANDIDATES_QUERY = <<~GRAPHQL.freeze
  query Candidates($projectRef: ID!) {
    projectCandidateCheckpoints(projectRef: $projectRef) {
      nodes { id repositoryId }
      pageInfo { hasNextPage }
    }
  }
GRAPHQL

DELIVERY_OBLIGATIONS_QUERY = <<~GRAPHQL.freeze
  query Obligations($projectRef: ID!) {
    projectVerificationObligations(projectRef: $projectRef) {
      nodes { id sourceRepositoryId targetRepositoryId }
      pageInfo { hasNextPage }
    }
  }
GRAPHQL

DELIVERY_MERGES_QUERY = <<~GRAPHQL.freeze
  query Merges($projectRef: ID!) {
    projectMergeSnapshots(projectRef: $projectRef) {
      nodes { id repositoryId }
      pageInfo { hasNextPage }
    }
  }
GRAPHQL

DELIVERY_RELEASES_QUERY = <<~GRAPHQL.freeze
  query Releases($projectRef: ID!) {
    projectReleaseSets(projectRef: $projectRef) {
      nodes { id repositoryIds }
      pageInfo { hasNextPage }
    }
  }
GRAPHQL

DELIVERY_CANDIDATE_DETAIL_QUERY = <<~GRAPHQL.freeze
  query Candidate($projectRef: ID!, $candidateId: ID!) {
    projectCandidateCheckpoint(projectRef: $projectRef, candidateId: $candidateId, first: 1) {
      checkpoint { id }
      impactRelationships {
        nodes { counterpart { id } relationshipKind reasons { kind matches } }
        pageInfo { endCursor hasNextPage }
      }
    }
  }
GRAPHQL

DELIVERY_VERIFICATION_DETAIL_QUERY = <<~GRAPHQL.freeze
  query Verification($projectRef: ID!, $obligationId: ID!) {
    projectVerificationObligation(
      projectRef: $projectRef
      obligationId: $obligationId
      evidenceFirst: 1
    ) {
      obligation { id status }
      evidence {
        nodes { id evidenceKind conclusion resultDigest }
        pageInfo { endCursor hasNextPage }
      }
      reasons { kind matches }
    }
  }
GRAPHQL

DELIVERY_MERGE_DETAIL_QUERY = <<~GRAPHQL.freeze
  query Merge($projectRef: ID!, $mergeSnapshotId: ID!) {
    projectMergeSnapshot(
      projectRef: $projectRef
      mergeSnapshotId: $mergeSnapshotId
      authorizationsFirst: 1
    ) {
      snapshot { id }
      candidates { id }
      authorizations {
        nodes { id outcome reasonCount decisionDigest }
        pageInfo { endCursor hasNextPage }
      }
    }
  }
GRAPHQL

DELIVERY_RELEASE_DETAIL_QUERY = <<~GRAPHQL.freeze
  query Release($projectRef: ID!, $releaseSetId: ID!) {
    projectReleaseSet(projectRef: $projectRef, releaseSetId: $releaseSetId) {
      releaseSet { id }
      members { repositoryId mergeSnapshotId }
      integrations { repositoryId attemptId outcome }
    }
  }
GRAPHQL

DELIVERY_BATCH_QUERY = <<~GRAPHQL.freeze
  query Batches {
    operationBatches {
      nodes { id targetTool status total }
      pageInfo { hasNextPage }
    }
  }
GRAPHQL

DELIVERY_BATCH_DETAIL_QUERY = <<~GRAPHQL.freeze
  query Batch($batchId: ID!) {
    operationBatch(batchId: $batchId) {
      batch { id status }
      items {
        nodes { index commandId targetTool status outcomeStatus outcomeSummary outcomeCode }
        pageInfo { hasNextPage }
      }
    }
  }
GRAPHQL

Given("a projected Project has delivery facts in two member Repositories and an unrelated Repository") do
  @delivery_scope = "project:cucumber-delivery"
  @delivery_repository_id = "018f0f4d-4e45-7abc-8def-000000000081"
  @delivery_member_repository_id = "018f0f4d-4e45-7abc-8def-000000000082"
  @delivery_other_repository_id = "018f0f4d-4e45-7abc-8def-000000000083"
  create_delivery_repository(@delivery_repository_id, @delivery_scope)
  create_delivery_repository(@delivery_member_repository_id, @delivery_scope)
  create_delivery_repository(@delivery_other_repository_id, "project:cucumber-delivery-other")
  @delivery_project_ref = Coordinator::Read::Web::ProjectReference.new.encode(scope: @delivery_scope)
  FactoryBot.create(
    :coordinator_read_candidate,
    candidate_id: "CAN-cucumber-delivery-a",
    repository_id: @delivery_repository_id,
    submitted_global_position: 101
  )
  FactoryBot.create(
    :coordinator_read_candidate,
    candidate_id: "CAN-cucumber-delivery-b",
    repository_id: @delivery_member_repository_id,
    head_commit_oid: "c" * 40,
    submitted_global_position: 102
  )
  FactoryBot.create(
    :coordinator_read_candidate,
    candidate_id: "CAN-cucumber-delivery-unrelated",
    repository_id: @delivery_other_repository_id,
    head_commit_oid: "d" * 40,
    submitted_global_position: 103
  )
  FactoryBot.create(
    :coordinator_read_verification_obligation,
    obligation_id: "OBL-cucumber-delivery",
    source_repository_id: @delivery_member_repository_id,
    target_repository_id: @delivery_other_repository_id,
    event_global_position: 201
  )
  FactoryBot.create(
    :coordinator_read_merge_snapshot,
    merge_snapshot_id: "MS-cucumber-delivery",
    repository_id: @delivery_member_repository_id,
    registered_global_position: 301
  )
  FactoryBot.create(
    :coordinator_read_release_set,
    release_set_id: "RS-cucumber-delivery",
    repository_ids: [ @delivery_repository_id, @delivery_other_repository_id ],
    prepared_global_position: 401
  )
end

When("the browser queries each focused delivery collection") do
  variables = { projectRef: @delivery_project_ref }
  @delivery_candidates_payload = query_project_delivery(DELIVERY_CANDIDATES_QUERY, variables)
  @delivery_obligations_payload = query_project_delivery(DELIVERY_OBLIGATIONS_QUERY, variables)
  @delivery_merges_payload = query_project_delivery(DELIVERY_MERGES_QUERY, variables)
  @delivery_releases_payload = query_project_delivery(DELIVERY_RELEASES_QUERY, variables)
end

Then("Candidates, obligations, merge snapshots, and ReleaseSets stay within the exact Project") do
  candidates = project_delivery_data(@delivery_candidates_payload).fetch("projectCandidateCheckpoints")
  obligations = project_delivery_data(@delivery_obligations_payload).fetch("projectVerificationObligations")
  merges = project_delivery_data(@delivery_merges_payload).fetch("projectMergeSnapshots")
  releases = project_delivery_data(@delivery_releases_payload).fetch("projectReleaseSets")
  assert_acceptance(
    candidates.fetch("nodes").map { _1.fetch("id") }.sort ==
      %w[CAN-cucumber-delivery-a CAN-cucumber-delivery-b],
    "Candidate Project membership failed"
  )
  assert_acceptance(
    obligations.fetch("nodes").map { _1.fetch("id") } == [ "OBL-cucumber-delivery" ],
    "Verification relationship was not resolved"
  )
  assert_acceptance(
    merges.fetch("nodes").map { _1.fetch("id") } == [ "MS-cucumber-delivery" ],
    "Merge Project membership failed"
  )
  assert_acceptance(
    releases.dig("nodes", 0, "repositoryIds") ==
      [ @delivery_repository_id, @delivery_other_repository_id ],
    "ReleaseSet ordered-member relationship was not preserved"
  )
end

Given("projected delivery details contain multiple supporting facts") do
  step "a projected Project has delivery facts in two member Repositories and an unrelated Repository"
  @delivery_detail_candidate = FactoryBot.create(
    :coordinator_read_candidate,
    :manifest_observed,
    candidate_id: "CAN-cucumber-detail",
    change_set_id: "CS-cucumber-detail",
    repository_id: @delivery_member_repository_id,
    submitted_global_position: 110
  )
  @delivery_counterparts = 2.times.map do |index|
    FactoryBot.create(
      :coordinator_read_candidate,
      :manifest_observed,
      candidate_id: "CAN-cucumber-counterpart-#{index + 1}",
      change_set_id: "CS-cucumber-detail",
      repository_id: @delivery_member_repository_id,
      head_commit_oid: (index + 4).to_s * 40,
      submitted_global_position: 111 + index
    )
  end
  [ @delivery_detail_candidate, *@delivery_counterparts ].each do |checkpoint|
    FactoryBot.create(
      :coordinator_read_candidate_changed_resource,
      candidate_id: checkpoint.candidate_id,
      change_set_id: checkpoint.change_set_id,
      repository_id: @delivery_member_repository_id,
      path: "lib/shared.rb"
    )
  end
  @delivery_obligation = Coordinator::Read::VerificationObligation.find("OBL-cucumber-delivery")
  @delivery_evidence = 2.times.map do |index|
    FactoryBot.create(
      :coordinator_read_verification_obligation_evidence_item,
      obligation_id: @delivery_obligation.obligation_id,
      assessment_input_digest: "sha256:#{(index + 5).to_s * 64}",
      result_digest: "sha256:#{(index + 7).to_s * 64}",
      stream_revision: 2 + index,
      event_global_position: 202 + index
    )
  end
  @delivery_authorizations = 2.times.map do |index|
    FactoryBot.create(
      :coordinator_read_merge_authorization,
      merge_snapshot_id: "MS-cucumber-delivery",
      input_digest: "sha256:#{(index + 1).to_s * 64}",
      decision_digest: "sha256:#{(index + 3).to_s * 64}",
      source_global_position: 302 + index
    )
  end
end

When("the browser queries each focused delivery detail with a one-item evidence page") do
  common = { projectRef: @delivery_project_ref }
  @delivery_candidate_payload = query_project_delivery(
    DELIVERY_CANDIDATE_DETAIL_QUERY,
    **common,
    candidateId: @delivery_detail_candidate.candidate_id
  )
  @delivery_verification_payload = query_project_delivery(
    DELIVERY_VERIFICATION_DETAIL_QUERY,
    **common,
    obligationId: @delivery_obligation.obligation_id
  )
  @delivery_merge_payload = query_project_delivery(
    DELIVERY_MERGE_DETAIL_QUERY,
    **common,
    mergeSnapshotId: "MS-cucumber-delivery"
  )
  @delivery_release_payload = query_project_delivery(
    DELIVERY_RELEASE_DETAIL_QUERY,
    **common,
    releaseSetId: "RS-cucumber-delivery"
  )
end

Then("every detail stays typed and advertises only its own next evidence page") do
  candidate = project_delivery_data(@delivery_candidate_payload).fetch("projectCandidateCheckpoint")
  verification = project_delivery_data(@delivery_verification_payload).fetch("projectVerificationObligation")
  merge = project_delivery_data(@delivery_merge_payload).fetch("projectMergeSnapshot")
  release = project_delivery_data(@delivery_release_payload).fetch("projectReleaseSet")
  assert_acceptance(
    candidate.dig("impactRelationships", "pageInfo", "hasNextPage"),
    "Candidate impacts were not independently bounded"
  )
  assert_acceptance(
    verification.dig("evidence", "pageInfo", "hasNextPage"),
    "Verification evidence was not independently bounded"
  )
  assert_acceptance(
    merge.dig("authorizations", "pageInfo", "hasNextPage"),
    "Merge authorizations were not independently bounded"
  )
  assert_acceptance(release.fetch("members").length == 2, "ReleaseSet detail is incomplete")
  serialized = JSON.generate(candidate:, verification:, merge:, release:)
  %w[submission evaluation source_metadata normalized projectDelivery].each do |private_field|
    assert_acceptance(!serialized.include?(private_field), "Private field #{private_field} leaked")
  end
end

Given("projected operation batches contain commands mentioning separate projects") do
  @delivery_batch = FactoryBot.create(
    :coordinator_read_operation_batch,
    batch_id: "018f0f4d-4e45-7abc-8def-000000000091",
    created_global_position: 501
  )
  item = FactoryBot.create(
    :coordinator_read_operation_batch_item,
    operation_batch: @delivery_batch,
    item_index: 0,
    command_id: "cucumber-batch-item",
    arguments: {
      "command_id" => "cucumber-batch-item",
      "actor" => { "kind" => "agent", "id" => "cucumber-agent" },
      "scope" => "project:must-not-be-inferred",
      "path" => "docs/private.md"
    }
  )
  FactoryBot.create(
    :coordinator_read_operation_batch_outcome,
    operation_batch: @delivery_batch,
    item_index: 0,
    command_id: item.command_id,
    outcome_global_position: 502
  )
end

When("the browser queries global operation batches") do
  @delivery_batches_payload = query_project_delivery(DELIVERY_BATCH_QUERY)
  @delivery_batch_payload = query_project_delivery(
    DELIVERY_BATCH_DETAIL_QUERY,
    batchId: @delivery_batch.batch_id
  )
end

Then("typed batch outcomes are presented without inferred project ownership or raw arguments") do
  batches = project_delivery_data(@delivery_batches_payload).fetch("operationBatches")
  detail = project_delivery_data(@delivery_batch_payload).fetch("operationBatch")
  assert_acceptance(batches.dig("nodes", 0, "id") == @delivery_batch.batch_id, "Batch missing")
  assert_acceptance(
    detail.dig("items", "nodes", 0, "outcomeSummary") == "Skill revision published.",
    "Typed outcome summary missing"
  )
  serialized = JSON.generate(batches:, detail:)
  assert_acceptance(!serialized.include?("project:must-not-be-inferred"), "Project was inferred")
  assert_acceptance(!serialized.include?("docs/private.md"), "Raw arguments leaked")
  assert_acceptance(!serialized.include?("repositoryId"), "Batch gained project ownership")
end

def create_delivery_repository(repository_id, scope)
  FactoryBot.create(
    :coordinator_read_repository,
    repository_id:,
    repository_key: "delivery-cucumber-#{repository_id}",
    scope:
  )
end

def query_project_delivery(query, variables = {})
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! "localhost"
  session.post("/graphql", params: { query:, variables: }, as: :json)
  assert_acceptance(session.response.status == 200, "Delivery GraphQL returned HTTP #{session.response.status}")
  JSON.parse(session.response.body)
end

def project_delivery_data(payload)
  errors = payload.fetch("errors", [])
  assert_acceptance(errors.empty?, "Delivery GraphQL failed: #{errors.inspect}")
  payload.fetch("data")
end
