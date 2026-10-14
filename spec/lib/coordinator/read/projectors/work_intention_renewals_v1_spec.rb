# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::WorkIntentionRenewalsV1, :read_model do
  let(:fixture) { build(:coordinator_read_work_intention_renewal) }
  let(:renewal_id) { fixture.renewal_id }
  let(:member) { fixture.members.sole }
  let(:schemas) { Coordinator::Write::Events::OptimisticSagas }
  let(:repository) { Coordinator::Read::Repositories::WorkIntentionRenewals.new }
  subject(:projector) { described_class.new }

  it "projects failure and completed members idempotently with native event timestamps" do
    events = [
      event(schemas::WorkIntentionSetRenewalRequestedV1.new(renewal_id:, intention_set_id: fixture.intention_set_id,
        attempt_id: fixture.attempt_id, expires_at: fixture.expires_at.utc.iso8601(6)), revision: 0),
      event(schemas::WorkIntentionRenewalAssignedV1.new(renewal_id:, position: 0, intention_id: member.fetch("intention_id"),
        resource_id: member.fetch("resource_id"), fencing_token: 1, renew_command_id: SecureRandom.uuid_v7,
        outcome_command_id: SecureRandom.uuid_v7), revision: 1),
      event(schemas::WorkIntentionRenewalFailedV1.new(renewal_id:, intention_id: member.fetch("intention_id"),
        reason_code: "concurrency_conflict", reason: "Three races exhausted; retry with a new request", retryable: true, attempts: 3), revision: 2),
      event(schemas::WorkIntentionSetRenewalFailedV1.new(renewal_id:), revision: 3)
    ]
    projector.call(events)
    view = repository.fetch(renewal_id:)
    expect(view).to have_attributes(status: "failed", task_id: fixture.task_id, updated_at: events.last.created_at.utc.iso8601(6))
    expect(view.members.sole.status).to eq("failed")
    expect(view.members.sole.failure).to have_attributes(reason_code: "concurrency_conflict", attempts: 3, retryable: true)
    projector.call(events)
    expect(repository.fetch(renewal_id:)).to eq(view)
    expect(Coordinator::Read::WorkIntentionRenewal.count).to eq(1)
  end

  it "preserves header fields while completing one stable member in a later batch" do
    row = create(:coordinator_read_work_intention_renewal, renewal_id:, members: [ member ], status: "requested")
    header = row.attributes.slice("request_event", "actor_id", "actor_kind", "expires_at", "intention_set_id", "task_id")
    completed = event(schemas::WorkIntentionRenewalCompletedV1.new(renewal_id:,
      intention_id: member.fetch("intention_id"), renewal_event: nil), revision: 10)

    2.times { projector.call([ completed ]) }

    expect(row.reload.members.sole).to include("status" => "completed", "failure" => nil, "renewal_event" => nil)
    expect(row.attributes.slice(*header.keys)).to eq(header)
    expect(row.status).to eq("running")
  end

  it "does not erase a member outcome when its assignment is replayed" do
    row = create(:coordinator_read_work_intention_renewal, renewal_id:, members: [ member.merge("status" => "completed") ], status: "completed")
    assigned = event(schemas::WorkIntentionRenewalAssignedV1.new(renewal_id:, position: 0,
      intention_id: member.fetch("intention_id"), resource_id: member.fetch("resource_id"), fencing_token: 1,
      renew_command_id: SecureRandom.uuid_v7, outcome_command_id: SecureRandom.uuid_v7), revision: 1)

    projector.call([ assigned ])

    expect(row.reload.members.sole.fetch("status")).to eq("completed")
    expect(row.status).to eq("completed")
  end

  it "serves a stale requested projection by public Task ID without querying the write side" do
    create(:coordinator_read_work_intention_renewal, renewal_id:, task_id: fixture.task_id, status: "requested", updated_at: Time.now.utc - 3600)
    result = Coordinator::Read::Queries::WorkIntentionRenewalGet.new.call(task_id: fixture.task_id).value!
    expect(result.status).to eq("ok")
    expect(result.data.renewal).to have_attributes(renewal_id:, status: "requested")
  end

  it "validates exactly one lookup identity and reports an unobserved projection honestly" do
    query = Coordinator::Read::Queries::WorkIntentionRenewalGet.new
    expect(query.call({}).value!.status).to eq("invalid")
    expect(query.call(renewal_id:, task_id: fixture.task_id).value!.status).to eq("invalid")
    expect(query.call(renewal_id:).value!.status).to eq("not_found")
    expect(query.call(task_id: "not-a-uuid").value!.status).to eq("invalid")
  end

  it "uses the normal MCP result adapter and its explicit output schema" do
    record = create(:coordinator_read_work_intention_renewal)
    response = Coordinator::Mcp::Tools::WorkIntentionRenewalGet.call(task_id: record.task_id)
    expect(response.structured_content).to include(status: "ok")
    expect(response.structured_content.dig(:data, :renewal, :task_id)).to eq(record.task_id)
  end

  def event(payload, revision:)
    PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: payload.class.event_type,
      data: payload.to_h.deep_stringify_keys,
      metadata: { "schema_version" => 1, "command_id" => renewal_id, "actor_kind" => fixture.actor_kind,
        "actor_id" => fixture.actor_id, "task_id" => fixture.task_id },
      stream: PgEventstore::Stream.new(context: "DevelopmentCoordination", stream_name: "WorkIntentionSetRenewal", stream_id: renewal_id),
      stream_revision: revision, global_position: revision + 100, created_at: Time.now.utc + revision,
      markers: [ "renewal:#{renewal_id}" ], correlation_id: fixture.correlation_id)
  end
end
