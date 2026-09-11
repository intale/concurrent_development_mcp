# frozen_string_literal: true

RSpec.describe Coordinator::Read::Web::Queries::DeliveryBrowser, :read_model do
  let(:scope) { "project:delivery-browser" }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000081" }
  let(:member_repository_id) { "018f0f4d-4e45-7abc-8def-000000000082" }
  let(:other_repository_id) { "018f0f4d-4e45-7abc-8def-000000000083" }
  let(:change_set_id) { "CS-delivery-browser" }
  let(:project_ref) { Coordinator::Read::Web::ProjectReference.new.encode(scope:) }

  before do
    create_repository(repository_id, scope)
    create_repository(member_repository_id, scope)
    create_repository(other_repository_id, "project:other-delivery-browser")
  end

  it "pages each focused collection across every exact Project member" do
    newer = create(
      :coordinator_read_candidate,
      candidate_id: "CAN-delivery-newer",
      change_set_id:,
      repository_id: member_repository_id,
      submitted_global_position: 102,
      created_at: Time.utc(2026, 8, 30, 12, 2),
      updated_at: Time.utc(2026, 8, 30, 12, 2)
    )
    older = create(
      :coordinator_read_candidate,
      candidate_id: "CAN-delivery-older",
      change_set_id:,
      repository_id:,
      head_commit_oid: "c" * 40,
      submitted_global_position: 101,
      created_at: Time.utc(2026, 8, 30, 12, 1),
      updated_at: Time.utc(2026, 8, 30, 12, 1)
    )
    create(
      :coordinator_read_candidate,
      candidate_id: "CAN-delivery-unrelated",
      change_set_id:,
      repository_id: other_repository_id,
      head_commit_oid: "d" * 40,
      submitted_global_position: 103
    )
    obligation = create(
      :coordinator_read_verification_obligation,
      obligation_id: "OBL-delivery",
      change_set_id:,
      source_repository_id: member_repository_id,
      target_repository_id: other_repository_id,
      event_global_position: 202
    )
    snapshot = create(
      :coordinator_read_merge_snapshot,
      merge_snapshot_id: "MS-delivery",
      repository_id: member_repository_id,
      registered_global_position: 302
    )
    release = create(
      :coordinator_read_release_set,
      release_set_id: "RS-delivery",
      change_set_id:,
      repository_ids: [ member_repository_id, other_repository_id ],
      prepared_global_position: 402
    )

    first = query.candidates(project_ref:, first: 1, sort: "newest_first", change_set_id:)
    second = query.candidates(
      project_ref:,
      first: 1,
      sort: "newest_first",
      change_set_id:,
      after_updated_at: first.next_cursor.updated_at,
      after_id: first.next_cursor.id
    )
    obligations = query.obligations(project_ref:, status: "open")
    merges = query.merges(project_ref:)
    releases = query.releases(project_ref:, change_set_id:)

    expect(first.items.map(&:candidate_id)).to eq([ newer.candidate_id ])
    expect(second.items.map(&:candidate_id)).to eq([ older.candidate_id ])
    expect(obligations.items.map(&:obligation_id)).to eq([ obligation.obligation_id ])
    expect(merges.items.map(&:merge_snapshot_id)).to eq([ snapshot.merge_snapshot_id ])
    expect(releases.items.map(&:release_set_id)).to eq([ release.release_set_id ])
  end

  it "serves typed focused details with independently bounded nested evidence" do
    candidate = create(
      :coordinator_read_candidate,
      :manifest_observed,
      candidate_id: "CAN-delivery-detail",
      change_set_id:,
      repository_id: member_repository_id,
      submitted_global_position: 110
    )
    counterpart = create(
      :coordinator_read_candidate,
      :manifest_observed,
      candidate_id: "CAN-delivery-counterpart",
      change_set_id:,
      repository_id: member_repository_id,
      head_commit_oid: "c" * 40,
      submitted_global_position: 111
    )
    [ candidate, counterpart ].each do |checkpoint|
      create(
        :coordinator_read_candidate_changed_resource,
        candidate_id: checkpoint.candidate_id,
        change_set_id:,
        repository_id: member_repository_id,
        path: "lib/shared.rb"
      )
    end
    obligation = create(
      :coordinator_read_verification_obligation,
      obligation_id: "OBL-delivery-detail",
      change_set_id:,
      source_repository_id: member_repository_id,
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
      repository_id: member_repository_id,
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
      repository_ids: [ repository_id, member_repository_id ]
    )

    candidate_detail = query.candidate(project_ref:, candidate_id: candidate.candidate_id)
    verification_detail = query.verification(project_ref:, obligation_id: obligation.obligation_id)
    merge_detail = query.merge(project_ref:, merge_snapshot_id: snapshot.merge_snapshot_id)
    release_detail = query.release(project_ref:, release_set_id: release.release_set_id)

    expect(candidate_detail.impacts.relationships.map { _1.counterpart.candidate_id }).to eq(
      [ counterpart.candidate_id ]
    )
    expect(verification_detail.evidence.items.map(&:evidence_id)).to eq([ evidence.evidence_id ])
    expect(verification_detail.reasons.map(&:kind)).to eq([ "semantic_key_match" ])
    expect(merge_detail.authorizations.items.map(&:authorization_id)).to eq(
      [ authorization.authorization_id ]
    )
    expect(release_detail.members.map(&:repository_id)).to eq(
      [ repository_id, member_repository_id ]
    )
  end

  it "isolates focused details and rejects incomplete collection cursors" do
    create(
      :coordinator_read_candidate,
      candidate_id: "CAN-other-detail",
      repository_id: other_repository_id
    )

    expect do
      query.candidates(project_ref:, after_position: 1)
    end.to raise_error(Coordinator::Read::Web::DeliveryBrowserQueryError)
    expect(query.candidate(project_ref:, candidate_id: "CAN-other-detail")).to be_nil
    expect(query.candidates(project_ref: unknown_project_ref)).to be_nil
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

  def query
    described_class.new
  end

  def unknown_project_ref
    Coordinator::Read::Web::ProjectReference.new.encode(scope: "project:missing-delivery-browser")
  end

  def create_repository(id, repository_scope)
    create(
      :coordinator_read_repository,
      repository_id: id,
      repository_key: "delivery-#{id}",
      scope: repository_scope
    )
  end
end
