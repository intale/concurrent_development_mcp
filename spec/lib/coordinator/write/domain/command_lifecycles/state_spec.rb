# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::CommandLifecycles::State do
  let(:command_id) { "01919191-9191-7192-8191-919191919191" }
  let(:registered) do
    Coordinator::Write::Events::CommandRegisteredV1.new(
      command_id:,
      request_id: "request-101",
      tool_name: "change_set_create"
    )
  end

  it "folds registration metadata and a lean successful terminal fact" do
    succeeded = Coordinator::Write::Events::CommandSucceededV1.new(command_id:)

    state = described_class.reduce(
      [ registered, succeeded ],
      canonical_input_digests: [ "sha256:#{'a' * 64}", nil ]
    )

    expect(state.to_h).to include(
      command_id:,
      request_id: "request-101",
      tool_name: "change_set_create",
      canonical_input_digest: "sha256:#{'a' * 64}",
      status: "succeeded"
    )
  end

  it "folds the reason and retry signal of a rejected command" do
    rejected = Coordinator::Write::Events::CommandRejectedV2.new(
      command_id:,
      error: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetError.new(
        code: "change_set_already_exists",
        message: "ChangeSet already exists",
        details: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetDetails.new(
          change_set_id: "CS-command-state"
        )
      ),
      retryable: true
    )

    state = described_class.reduce([ registered, rejected ])

    expect(state.to_h).to include(
      status: "rejected",
      rejection_code: "change_set_already_exists",
      rejection_reason: "ChangeSet already exists",
      rejection_retryable: true
    )
  end

  it "rejects histories with contradictory terminal facts" do
    events = [
      registered,
      Coordinator::Write::Events::CommandSucceededV1.new(command_id:),
      Coordinator::Write::Events::CommandRejectedV2.new(
        command_id:,
        error: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetError.new(
          code: "change_set_already_exists",
          message: "Contradiction",
          details: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetDetails.new(
            change_set_id: "CS-command-state"
          )
        ),
        retryable: false
      )
    ]

    expect { described_class.reduce(events) }
      .to raise_error(Coordinator::Write::InvalidCommandHistory)
  end
end
