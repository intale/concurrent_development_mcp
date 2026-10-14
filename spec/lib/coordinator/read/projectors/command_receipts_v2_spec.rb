# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::CommandReceiptsV2, :read_model, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:facts) { Coordinator::Read::CommandResults::FactReader.new(event_store:) }
  let(:projector) { described_class.new(facts:) }
  let(:receipts) { Coordinator::Read::Repositories::CommandReceipts.new }
  let(:digest) { "sha256:#{'a' * 64}" }

  it "uses trusted facts for success and rejection and persists both in one bulk update" do
    success, effects = terminal_for("change_set_create", input: { change_set_id: "CS-success" })
    rejection, = terminal_for("change_set_create", input: { change_set_id: "CS-rejected" }, rejection: {
      code: "change_set_already_exists", message: "ChangeSet already exists", details: { change_set_id: "CS-rejected" }
    })
    sql = []
    ActiveSupport::Notifications.subscribed(->(*args) { sql << args.last.fetch(:sql) }, "sql.active_record") do
      projector.call([ success, rejection ])
    end

    good, bad = receipts.fetch(success.stream.stream_id), receipts.fetch(rejection.stream.stream_id)
    expect(good).to have_attributes(status: "ok", receipt: good.command_id, summary: "ChangeSet created.")
    expect(good.data.change_set_id).to eq("CS-success")
    expect(good.emitted_events.map(&:event_id)).to eq(effects.map(&:id))
    expect(bad).to have_attributes(status: "denied", receipt: nil, summary: "ChangeSet already exists")
    expect(sql.count { _1.start_with?("UPDATE") }).to eq(1)
  end

  it "reprocesses the same immutable terminal without a claim ledger or duplicate receipt" do
    terminal, = terminal_for("change_set_create", input: { change_set_id: "CS-replay" })
    2.times { projector.call([ terminal ]) }

    expect(Coordinator::Read::CommandReceipt.count).to eq(1)
    expect(receipts.fetch(terminal.stream.stream_id).data.change_set_id).to eq("CS-replay")
    expect(Coordinator::Read::CommandReceipt.sole.updated_at).to eq(terminal.created_at)
  end

  it "repairs an existing projected receipt from ordinary terminal replay" do
    terminal, = terminal_for("change_set_create", input: { change_set_id: "CS-repaired" })
    row = create(:coordinator_read_command_receipt, command_id: terminal.stream.stream_id,
      request_id: "receipt-request-#{terminal.stream.stream_id}", summary: "Incorrect projection")
    original_created_at = row.created_at

    projector.call([ terminal ])

    expect(row.reload.summary).to eq("ChangeSet created.")
    expect(row.created_at).to eq(original_created_at)
    expect(receipts.fetch(terminal.stream.stream_id).data.change_set_id).to eq("CS-repaired")
  end

  it "does not decode or revalidate immutable event schema metadata" do
    terminal, = terminal_for("change_set_create", input: { change_set_id: "CS-trusted" }, schema_version: 999)
    projector.call([ terminal ])

    expect(receipts.fetch(terminal.stream.stream_id).data.change_set_id).to eq("CS-trusted")
  end

  it "omits internal policy commands without a public instruction" do
    id = SecureRandom.uuid_v7
    append(:command, id, "CommandRegistered", { command_id: id, request_id: "internal-policy", tool_name: "coordination-policy" }, owner: id)
    terminal = append(:command, id, "CommandSucceeded", { command_id: id }, owner: id)

    projector.call([ terminal ])

    expect(Coordinator::Read::CommandReceipt.count).to eq(0)
  end

  it "presents an exhausted Saga as failure with its explicit committed-effects context" do
    terminal, = terminal_for("change_set_create", input: { change_set_id: "CS-partial" }, failure: {
      failed_step: "save-goal", reason_code: "revision_conflict", reason: "Retry the command", retryable: true,
      effects_committed: true, attempts: 3
    })
    projector.call([ terminal ])

    result = receipts.fetch(terminal.stream.stream_id)
    expect(result).to have_attributes(status: "failed", receipt: nil, summary: "Retry the command")
    expect(result.semantic_result.completion).to have_attributes(outcome: "partial_failure", effects: "partial", read_back_required: false)
  end

  it "uses the exact Skill publication when a no-op receipt is delivered after a later publication" do
    skill_id = SecureRandom.uuid_v7
    marker = Coordinator::Shared::Markers::CodecV2.encode(purpose: "skill-natural-key", components: [
      { dimension: "name", value: "trusted-receipt" }, { dimension: "scope", value: "project:receipts" }
    ])
    append(:skill, skill_id, "SkillRegistered", { skill_id:, name: "trusted-receipt", scope: "project:receipts" }, markers: [ marker ])
    selected = append(:skill, skill_id, "SkillRevisionPublished", { skill_id:, skill_revision_id: SecureRandom.uuid_v7, revision: 1 })
    terminal, = terminal_for("skill_publish", input: { skill_id: SecureRandom.uuid_v7, name: "trusted-receipt", scope: "project:receipts",
      expected_revision: 1, description: "Review", instructions: "Inspect facts", assets: [], content_digest: digest }, effects: false)
    append(:skill, skill_id, "SkillRevisionPublished", { skill_id:, skill_revision_id: SecureRandom.uuid_v7, revision: 2 })

    projector.call([ terminal ])

    result = receipts.fetch(terminal.stream.stream_id)
    expect(result.data).to have_attributes(skill_id:, revision: 1, published_at: selected.created_at.utc.iso8601(6))
    expect(result.data.publication_event.event_id).to eq(selected.id)
    expect(result.emitted_events).to be_empty
  end

  it "has one presentation path for every current public command without using its command builder" do
    presented = Coordinator::Read::CommandResults::Assembler::PRESENTERS.flat_map { _1::TOOLS }
    expect(presented.sort).to eq(Coordinator::Write::Tasks::TargetContractRegistry.tool_names.sort)
    expect(presented.uniq.length).to eq(presented.length)
  end

  def terminal_for(tool, input:, rejection: nil, failure: nil, schema_version: 1, effects: true)
    id = SecureRandom.uuid_v7
    append(:command, id, "CommandRegistered", { command_id: id, request_id: "receipt-request-#{id}", tool_name: tool }, owner: id, schema_version:)
    append(:coordination_task, SecureRandom.uuid_v7, "CoordinationTaskSubmitted", {
      task_id: SecureRandom.uuid_v7, command_id: id, tool_name: tool, poll_interval_ms: 500, ttl_ms: nil,
      command_input: { schema: "command-input/v1", command_id: id, tool_name: tool, input: }
    }, owner: id, schema_version:)
    effect_events = if effects
                      [ append(:change_set, input.fetch(:change_set_id, "CS-fixture"), "ChangeSetCreated",
                        { change_set_id: input.fetch(:change_set_id, "CS-fixture") }, owner: id, schema_version:) ]
    else []
    end
    type, data = if rejection
                   [ "CommandRejected", { command_id: id, error: rejection, retryable: false } ]
    elsif failure
                   [ "CommandExecutionFailed", failure.merge(command_id: id) ]
    else
                   [ "CommandSucceeded", { command_id: id } ]
    end
    [ append(:command, id, type, data, owner: id, schema_version:), effect_events ]
  end

  def append(stream, id, type, data, owner: "receipt-fixtures", markers: [], schema_version: 1)
    event = TrustedProjectionEventFactory.new.build(type:, data:,
      metadata: { "command_id" => owner, "canonical_input_digest" => digest, "schema_version" => schema_version,
        "actor_kind" => "agent", "actor_id" => "receipt-fixtures", "recorded_by" => "coordinator", "policy_version" => "receipt-fixtures/v1" },
      markers: markers + [ "command:#{owner}" ])
    event_store.append(streams.public_send(stream, id), [ event ]).sole
  end
end
