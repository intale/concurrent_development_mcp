# frozen_string_literal: true

RSpec.describe "Command terminal transitions" do
  let(:command_id) { "01919191-9191-7192-8191-919191919191" }
  let(:registered) do
    Coordinator::Write::Events::CommandRegisteredV1.new(
      command_id:,
      request_id: "request-101",
      tool_name: "change_set_create"
    )
  end
  let(:registered_state) do
    Coordinator::Write::Domain::CommandLifecycles::State.reduce([ registered ])
  end

  it "Given a registered command, when it succeeds, then it emits only CommandSucceeded" do
    command = Coordinator::Write::Commands::SucceedCommand.new(command_id:)

    result = Coordinator::Write::Domain::CommandLifecycles::Succeed.new.call(
      state: registered_state,
      command:
    )

    expect(result.value!).to eq(Coordinator::Write::Events::CommandSucceededV1.new(command_id:))
  end

  it "Given the same success already recorded, when success is retried, then it emits nothing" do
    state = Coordinator::Write::Domain::CommandLifecycles::State.reduce(
      [ registered, Coordinator::Write::Events::CommandSucceededV1.new(command_id:) ]
    )
    command = Coordinator::Write::Commands::SucceedCommand.new(command_id:)

    expect(Coordinator::Write::Domain::CommandLifecycles::Succeed.new.call(state:, command:).value!).to be_nil
  end

  it "Given a registered command, when it is rejected, then it emits only CommandRejected" do
    command = rejection_command

    result = Coordinator::Write::Domain::CommandLifecycles::Reject.new.call(
      state: registered_state,
      command:
    )

    expect(result.value!).to eq(
      Coordinator::Write::Events::CommandRejectedV2.new(command.to_h)
    )
  end

  it "Given the same rejection already recorded, when rejection is retried, then it emits nothing" do
    state = Coordinator::Write::Domain::CommandLifecycles::State.reduce(
      [ registered, Coordinator::Write::Events::CommandRejectedV2.new(rejection_command.to_h) ]
    )

    expect(
      Coordinator::Write::Domain::CommandLifecycles::Reject.new.call(
        state:,
        command: rejection_command
      ).value!
    ).to be_nil
  end

  it "rejects a terminal outcome that contradicts the durable outcome" do
    state = Coordinator::Write::Domain::CommandLifecycles::State.reduce(
      [ registered, Coordinator::Write::Events::CommandSucceededV1.new(command_id:) ]
    )

    result = Coordinator::Write::Domain::CommandLifecycles::Reject.new.call(
      state:,
      command: rejection_command
    )

    expect(result).to be_failure
    expect(result.failure.code).to eq(:command_terminal)
  end

  def rejection_command
    Coordinator::Write::Commands::RejectCommand.new(
      command_id:,
      error: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetError.new(
        code: "change_set_already_exists",
        message: "ChangeSet already exists",
        details: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetDetails.new(
          change_set_id: "CS-command-transition"
        )
      ),
      retryable: true
    )
  end
end
