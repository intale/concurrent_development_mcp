# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::CoordContext, :read_model do
  subject(:query) { described_class.new }

  it "serves an available context immediately and supports observed-view cache tokens" do
    expect(query.call(work_item_id: "W-100").value!.status).to eq("not_found")

    create(
      :coordinator_read_coord_context,
      change_set_id: "CS-100",
      work_item_id: "W-100",
      attempt_id: "A-100"
    )
    create(
      :coordinator_read_coord_context_scope,
      change_set_id: "CS-100",
      scope_kind: "work_item",
      scope_id: "W-100"
    )

    current = query.call(work_item_id: "W-100").value!
    expect(current.status).to eq("ok")
    expect(current.data.context.work_items.sole.work_item_id).to eq("W-100")
    expect(current.to_h).not_to include(:projection_status)

    unchanged = query.call(work_item_id: "W-100", context_token: current.context_token).value!
    expect(unchanged.status).to eq("not_modified")
    expect(unchanged.context_token).to eq(current.context_token)
  end

  it "ignores source barriers for history evicted from the bounded embedded context" do
    stale_positions = Array.new(300) do |index|
      {
        "stream_context" => "DevelopmentExecution",
        "stream_name" => "Attempt",
        "stream_id" => "A-stale-#{index}",
        "stream_revision" => 3
      }
    end
    context = build(
      :coordinator_read_coord_context,
      change_set_id: "CS-bounded",
      work_item_id: "W-bounded",
      attempt_id: "A-current"
    )
    context.source_positions += stale_positions
    context.save!
    create(
      :coordinator_read_coord_context_scope,
      change_set_id: "CS-bounded",
      scope_kind: "change_set",
      scope_id: "CS-bounded"
    )

    result = query.call(change_set_id: "CS-bounded").value!

    expect(result.status).to eq("ok")
    expect(result.context_token).to match(/\Asha256:[0-9a-f]{64}\z/)
  end

  it "resolves exact ChangeSet and Attempt projection scopes" do
    create(
      :coordinator_read_coord_context,
      change_set_id: "CS-scopes",
      work_item_id: "W-scopes",
      attempt_id: "A-scopes"
    )
    %w[change_set attempt].each do |kind|
      identifier = kind == "change_set" ? "CS-scopes" : "A-scopes"
      create(
        :coordinator_read_coord_context_scope,
        change_set_id: "CS-scopes",
        scope_kind: kind,
        scope_id: identifier
      )
    end

    change_set = query.call(change_set_id: "CS-scopes").value!
    attempt = query.call(attempt_id: "A-scopes").value!

    expect(change_set.data.scope).to have_attributes(change_set_id: "CS-scopes")
    expect(attempt.data.scope).to have_attributes(
      change_set_id: "CS-scopes",
      work_item_id: "W-scopes",
      attempt_id: "A-scopes"
    )
  end

  it "rejects ambiguous roots and the removed causal-freshness parameter" do
    expect(query.call(change_set_id: "CS-100", work_item_id: "W-100").value!.status).to eq("invalid")
    expect(query.call(change_set_id: "CS-100", after_command_id: "cmd-other").value!.status).to eq("invalid")
  end
end
