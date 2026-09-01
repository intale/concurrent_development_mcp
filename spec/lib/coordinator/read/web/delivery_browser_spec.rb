# frozen_string_literal: true

RSpec.describe Coordinator::Read::Web::Queries::DeliveryBrowser, :read_model do
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000081" }
  let(:other_repository_id) { "018f0f4d-4e45-7abc-8def-000000000082" }
  let(:change_set_id) { "CS-delivery-browser" }

  before do
    create(
      :coordinator_read_repository,
      repository_id:,
      repository_key: "delivery-browser",
      scope: "project:delivery-browser",
      display_name: "Delivery browser"
    )
    create(
      :coordinator_read_repository,
      repository_id: other_repository_id,
      repository_key: "other-delivery-browser",
      scope: "project:other-delivery-browser"
    )
  end

  it "lists only deterministically project-related delivery projections with stable pages" do
    candidate = create(
      :coordinator_read_candidate,
      candidate_id: "CAN-delivery-newer",
      change_set_id:,
      repository_id:,
      submitted_global_position: 102
    )
    older_candidate = create(
      :coordinator_read_candidate,
      candidate_id: "CAN-delivery-older",
      change_set_id:,
      repository_id:,
      head_commit_oid: "c" * 40,
      submitted_global_position: 101
    )
    create(
      :coordinator_read_candidate,
      candidate_id: "CAN-delivery-other",
      change_set_id:,
      repository_id: other_repository_id,
      head_commit_oid: "d" * 40,
      submitted_global_position: 103
    )
    obligation = create(
      :coordinator_read_verification_obligation,
      obligation_id: "OBL-delivery",
      change_set_id:,
      source_repository_id: repository_id,
      target_repository_id: other_repository_id,
      event_global_position: 202
    )
    snapshot = create(
      :coordinator_read_merge_snapshot,
      merge_snapshot_id: "MS-delivery",
      repository_id:,
      registered_global_position: 302
    )
    release = create(
      :coordinator_read_release_set,
      release_set_id: "RS-delivery",
      change_set_id:,
      repository_ids: [ repository_id, other_repository_id ],
      prepared_global_position: 402
    )

    first = query.catalog(repository_id:, first: 1, sort: "newest_first")
    second = query.catalog(
      repository_id:,
      first: 1,
      sort: "newest_first",
      candidate_after_position: first.candidates.next_cursor.position,
      candidate_after_id: first.candidates.next_cursor.id
    )

    expect(first.project).to have_attributes(repository_id:, display_name: "Delivery browser")
    expect(first.candidates.items.map(&:candidate_id)).to eq([ candidate.candidate_id ])
    expect(second.candidates.items.map(&:candidate_id)).to eq([ older_candidate.candidate_id ])
    expect(first.obligations.items.map(&:obligation_id)).to eq([ obligation.obligation_id ])
    expect(first.merge_snapshots.items.map(&:merge_snapshot_id)).to eq([ snapshot.merge_snapshot_id ])
    expect(first.release_sets.items.map(&:release_set_id)).to eq([ release.release_set_id ])
  end

  it "serves typed Candidate impacts, verification evidence, merge authorizations, and ReleaseSet details" do
    candidate = create(
      :coordinator_read_candidate,
      :manifest_observed,
      candidate_id: "CAN-delivery-detail",
      change_set_id:,
      repository_id:,
      submitted_global_position: 110
    )
    counterpart = create(
      :coordinator_read_candidate,
      :manifest_observed,
      candidate_id: "CAN-delivery-counterpart",
      change_set_id:,
      repository_id:,
      head_commit_oid: "c" * 40,
      submitted_global_position: 111
    )
    create(
      :coordinator_read_candidate_changed_resource,
      candidate_id: candidate.candidate_id,
      change_set_id:,
      repository_id:,
      path: "lib/shared.rb"
    )
    create(
      :coordinator_read_candidate_changed_resource,
      candidate_id: counterpart.candidate_id,
      change_set_id:,
      repository_id:,
      path: "lib/shared.rb"
    )
    obligation = create(
      :coordinator_read_verification_obligation,
      obligation_id: "OBL-delivery-detail",
      change_set_id:,
      source_repository_id: repository_id,
      target_repository_id: other_repository_id,
      event_global_position: 210
    )
    evidence = create(
      :coordinator_read_verification_obligation_evidence_item,
      obligation_id: obligation.obligation_id,
      event_global_position: 211
    )
    snapshot = create(
      :coordinator_read_merge_snapshot,
      merge_snapshot_id: "MS-delivery-detail",
      repository_id:,
      registered_global_position: 310
    )
    authorization = create(
      :coordinator_read_merge_authorization,
      merge_snapshot_id: snapshot.merge_snapshot_id,
      source_global_position: 311
    )
    release = create(
      :coordinator_read_release_set,
      release_set_id: "RS-delivery-detail",
      change_set_id:,
      repository_ids: [ repository_id, other_repository_id ]
    )

    candidate_detail = query.candidate(repository_id:, candidate_id: candidate.candidate_id)
    verification_detail = query.verification(repository_id:, obligation_id: obligation.obligation_id)
    merge_detail = query.merge(repository_id:, merge_snapshot_id: snapshot.merge_snapshot_id)
    release_detail = query.release(repository_id:, release_set_id: release.release_set_id)

    expect(candidate_detail.impacts.relationships.map { _1.counterpart.candidate_id }).to eq(
      [ counterpart.candidate_id ]
    )
    expect(verification_detail.evidence.items.map(&:evidence_id)).to eq([ evidence.evidence_id ])
    expect(verification_detail.reasons.map(&:kind)).to eq([ "semantic_key_match" ])
    expect(merge_detail.authorizations.items.map(&:authorization_id)).to eq(
      [ authorization.authorization_id ]
    )
    expect(merge_detail.candidates.map(&:candidate_id)).to eq(
      snapshot.ordered_candidates.map { _1.fetch("candidate_id") }
    )
    expect(release_detail.members.map(&:repository_id)).to eq([ repository_id, other_repository_id ])
  end

  it "keeps operation batches global while exposing typed bounded outcomes" do
    batch = create(
      :coordinator_read_operation_batch,
      batch_id: "018f0f4d-4e45-7abc-8def-000000000091",
      created_global_position: 501
    )
    first_item = create(
      :coordinator_read_operation_batch_item,
      operation_batch: batch,
      item_index: 0,
      command_id: "batch-item-zero"
    )
    create(
      :coordinator_read_operation_batch_item,
      operation_batch: batch,
      item_index: 1,
      command_id: "batch-item-one"
    )
    create(
      :coordinator_read_operation_batch_outcome,
      operation_batch: batch,
      item_index: first_item.item_index,
      command_id: first_item.command_id,
      outcome_global_position: 502
    )

    page = query.batches(first: 20, target_tool: "skill_publish")
    detail = query.batch(batch_id: batch.batch_id, first: 1)

    expect(page.items.map(&:batch_id)).to eq([ batch.batch_id ])
    expect(detail.items.items.first).to have_attributes(
      command_id: "batch-item-zero",
      status: "succeeded",
      outcome_status: "ok",
      outcome_summary: "Skill revision published."
    )
    expect(detail.items).to have_attributes(has_more: true, next_index: 0)
  end

  it "rejects partial cursors and isolates every project detail" do
    create(
      :coordinator_read_candidate,
      candidate_id: "CAN-other-detail",
      repository_id: other_repository_id
    )

    expect do
      query.catalog(repository_id:, candidate_after_position: 1)
    end.to raise_error(Coordinator::Read::Web::DeliveryBrowserQueryError)
    expect(query.candidate(repository_id:, candidate_id: "CAN-other-detail")).to be_nil
  end

  def query
    described_class.new
  end
end
