# frozen_string_literal: true

RSpec.describe Coordinator::Write::Tasks::SemanticResultMapper do
  include Dry::Monads[:result]

  subject(:mapper) { described_class.new }

  it "maps a durable command completion into one semantic success" do
    completion = Coordinator::Write::Events::CommandCompletedV1.new(
      command_id: "cmd-semantic-success",
      tool_name: "change_set_create",
      canonical_input_digest: "sha256:#{'a' * 64}",
      status: "ok",
      summary: "ChangeSet created",
      receipt: "cmd-semantic-success",
      data: Coordinator::Write::CommandReceiptData::ChangeSet.new(
        change_set_id: "CS-semantic-success"
      ),
      warnings: [],
      next_actions: [],
      emitted_events: [],
      completed_at: "2026-08-29T08:00:00.000000Z"
    )

    result = mapper.call(
      Success(completion),
      command_id: completion.command_id,
      tool_name: completion.tool_name
    )

    expect(result).to be_a(Coordinator::Write::Tasks::SemanticResultV1::Success)
    expect(result).to have_attributes(
      kind: "success",
      command_id: completion.command_id,
      receipt: completion.receipt,
      data: completion.data
    )
    expect(result.to_h.keys).not_to include(:content, :structured_content, :is_error)
  end

  it "maps a public command denial into one typed semantic rejection" do
    error = Coordinator::Write::OutcomeError.new(
      code: :change_set_already_exists,
      message: "ChangeSet already exists",
      details: { change_set_id: "CS-semantic-denial" }
    )

    result = mapper.call(
      Failure(error),
      command_id: "cmd-semantic-denial",
      tool_name: "change_set_create"
    )

    expect(result).to be_a(Coordinator::Write::Tasks::SemanticResultV1::DomainRejection)
    expect(result).to have_attributes(
      kind: "domain_rejection",
      status: "denied",
      command_id: "cmd-semantic-denial",
      error: have_attributes(
        code: "change_set_already_exists",
        message: "ChangeSet already exists"
      )
    )
    expect(result.to_h.keys).not_to include(:content, :structured_content, :is_error)
  end

  it "defines a presentation status for every strict domain error code" do
    expect(described_class::STATUS_BY_CODE.keys).to match_array(
      Coordinator::Write::Tasks::DomainErrorV1::ERROR_CODES
    )
  end
end
