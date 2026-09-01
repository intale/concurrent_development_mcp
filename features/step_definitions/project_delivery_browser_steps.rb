# frozen_string_literal: true

PROJECT_DELIVERY_QUERY = <<~GRAPHQL.freeze
  query ProjectDelivery($repositoryId: ID!) {
    projectDelivery(repositoryId: $repositoryId) {
      project { id }
      candidates { nodes { id } pageInfo { hasNextPage } }
      obligations { nodes { id sourceRepositoryId targetRepositoryId } pageInfo { hasNextPage } }
      mergeSnapshots { nodes { id repositoryId } pageInfo { hasNextPage } }
      releaseSets { nodes { id repositoryIds } pageInfo { hasNextPage } }
    }
  }
GRAPHQL

PROJECT_DELIVERY_VERIFICATION_QUERY = <<~GRAPHQL.freeze
  query Verification($repositoryId: ID!, $obligationId: ID!) {
    projectVerificationObligation(repositoryId: $repositoryId, obligationId: $obligationId) {
      obligation { id status }
      evidence { nodes { id evidenceKind conclusion resultDigest } pageInfo { hasNextPage } }
      reasons { kind matches }
    }
  }
GRAPHQL

PROJECT_DELIVERY_MERGE_QUERY = <<~GRAPHQL.freeze
  query Merge($repositoryId: ID!, $mergeSnapshotId: ID!) {
    projectMergeSnapshot(repositoryId: $repositoryId, mergeSnapshotId: $mergeSnapshotId) {
      snapshot { id }
      candidates { id }
      authorizations { nodes { id outcome reasonCount decisionDigest } pageInfo { hasNextPage } }
    }
  }
GRAPHQL

PROJECT_DELIVERY_BATCH_QUERY = <<~GRAPHQL.freeze
  query Batches {
    operationBatches {
      nodes { id targetTool status total }
      pageInfo { hasNextPage }
    }
  }
GRAPHQL

PROJECT_DELIVERY_BATCH_DETAIL_QUERY = <<~GRAPHQL.freeze
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

Given("projected delivery rows contain exact and unrelated project facts") do
  @delivery_repository_id = "018f0f4d-4e45-7abc-8def-000000000081"
  @delivery_other_repository_id = "018f0f4d-4e45-7abc-8def-000000000082"
  FactoryBot.create(
    :coordinator_read_repository,
    repository_id: @delivery_repository_id,
    repository_key: "delivery-cucumber",
    scope: "project:cucumber-delivery"
  )
  FactoryBot.create(
    :coordinator_read_repository,
    repository_id: @delivery_other_repository_id,
    repository_key: "delivery-cucumber-other",
    scope: "project:cucumber-delivery-other"
  )
  FactoryBot.create(
    :coordinator_read_candidate,
    candidate_id: "CAN-cucumber-delivery",
    repository_id: @delivery_repository_id,
    submitted_global_position: 101
  )
  FactoryBot.create(
    :coordinator_read_candidate,
    candidate_id: "CAN-cucumber-delivery-other",
    repository_id: @delivery_other_repository_id,
    submitted_global_position: 102
  )
  FactoryBot.create(
    :coordinator_read_verification_obligation,
    obligation_id: "OBL-cucumber-delivery",
    source_repository_id: @delivery_repository_id,
    target_repository_id: @delivery_other_repository_id,
    event_global_position: 201
  )
  FactoryBot.create(
    :coordinator_read_merge_snapshot,
    merge_snapshot_id: "MS-cucumber-delivery",
    repository_id: @delivery_repository_id,
    registered_global_position: 301
  )
  FactoryBot.create(
    :coordinator_read_release_set,
    release_set_id: "RS-cucumber-delivery",
    repository_ids: [ @delivery_repository_id, @delivery_other_repository_id ],
    prepared_global_position: 401
  )
end

When("the browser queries the projected project delivery") do
  @delivery_payload = query_project_delivery(
    PROJECT_DELIVERY_QUERY,
    repositoryId: @delivery_repository_id
  )
end

Then("only delivery facts with persisted relationships to the exact project are presented") do
  result = project_delivery_data(@delivery_payload).fetch("projectDelivery")
  assert_acceptance(result.dig("project", "id") == @delivery_repository_id, "Wrong project")
  assert_acceptance(
    result.dig("candidates", "nodes").map { _1.fetch("id") } == [ "CAN-cucumber-delivery" ],
    "Candidate project isolation failed"
  )
  assert_acceptance(
    result.dig("obligations", "nodes").map { _1.fetch("id") } == [ "OBL-cucumber-delivery" ],
    "Verification relationship was not resolved"
  )
  assert_acceptance(
    result.dig("mergeSnapshots", "nodes").map { _1.fetch("id") } == [ "MS-cucumber-delivery" ],
    "Merge project isolation failed"
  )
  assert_acceptance(
    result.dig("releaseSets", "nodes", 0, "repositoryIds") ==
      [ @delivery_repository_id, @delivery_other_repository_id ],
    "ReleaseSet ordered-member relationship was not preserved"
  )
end

Given("projected delivery rows contain verification evidence and merge authorization history") do
  step "projected delivery rows contain exact and unrelated project facts"
  @delivery_obligation = Coordinator::Read::VerificationObligation.find("OBL-cucumber-delivery")
  @delivery_evidence = FactoryBot.create(
    :coordinator_read_verification_obligation_evidence_item,
    obligation_id: @delivery_obligation.obligation_id,
    event_global_position: 202
  )
  @delivery_authorization = FactoryBot.create(
    :coordinator_read_merge_authorization,
    merge_snapshot_id: "MS-cucumber-delivery",
    source_global_position: 302
  )
end

When("the browser queries the related delivery details") do
  @delivery_verification_payload = query_project_delivery(
    PROJECT_DELIVERY_VERIFICATION_QUERY,
    repositoryId: @delivery_repository_id,
    obligationId: @delivery_obligation.obligation_id
  )
  @delivery_merge_payload = query_project_delivery(
    PROJECT_DELIVERY_MERGE_QUERY,
    repositoryId: @delivery_repository_id,
    mergeSnapshotId: "MS-cucumber-delivery"
  )
end

Then("typed evidence and authorization facts are presented without normalized support rows") do
  verification = project_delivery_data(@delivery_verification_payload)
    .fetch("projectVerificationObligation")
  merge = project_delivery_data(@delivery_merge_payload).fetch("projectMergeSnapshot")
  assert_acceptance(
    verification.dig("evidence", "nodes", 0, "id") == @delivery_evidence.evidence_id,
    "Verification evidence is missing"
  )
  assert_acceptance(
    merge.dig("authorizations", "nodes", 0, "id") == @delivery_authorization.authorization_id,
    "Merge authorization is missing"
  )
  serialized = JSON.generate(verification: verification, merge: merge)
  %w[submission evaluation source_metadata normalized].each do |private_field|
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
  @delivery_batches_payload = query_project_delivery(PROJECT_DELIVERY_BATCH_QUERY)
  @delivery_batch_payload = query_project_delivery(
    PROJECT_DELIVERY_BATCH_DETAIL_QUERY,
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
  serialized = JSON.generate(batches: batches, detail: detail)
  assert_acceptance(!serialized.include?("project:must-not-be-inferred"), "Project was inferred")
  assert_acceptance(!serialized.include?("docs/private.md"), "Raw arguments leaked")
  assert_acceptance(!serialized.include?("repositoryId"), "Batch gained project ownership")
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
