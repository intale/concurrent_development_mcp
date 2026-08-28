# frozen_string_literal: true

RSpec.describe Coordinator::Mcp::Tasks::TerminalResultValidator do
  subject(:validator) { described_class.new }

  it "accepts a terminal result matching its persisted originating tool" do
    expect(validator.call(completed_state(data: change_set_receipt))).to be_a(
      Coordinator::Write::Domain::CoordinationTasks::State
    )
  end

  it "rejects a receipt belonging to another mutation family" do
    expect do
      validator.call(
        completed_state(
          data: Coordinator::Write::CommandReceiptData::WorkItem.new(
            change_set_id: "CS-terminal-schema",
            work_item_id: "W-terminal-schema"
          )
        )
      )
    end.to raise_error(::MCP::Tool::OutputSchema::ValidationError)
  end

  it "rejects an emitted action whose arguments violate the target input schema" do
    action = Coordinator::Write::NextAction.new(
      tool: "candidate_get",
      arguments: Coordinator::Write::NextAction::ChangeSetArguments.new(
        change_set_id: "CS-terminal-schema"
      )
    )

    expect do
      validator.call(completed_state(data: change_set_receipt, next_actions: [ action ]))
    end.to raise_error(::MCP::Tool::OutputSchema::ValidationError)
  end

  def completed_state(data:, next_actions: [])
    Coordinator::Write::Domain::CoordinationTasks::State.reduce(
      [ submitted_event, started_event, completed_event(data:, next_actions:) ]
    )
  end

  def submitted_event
    Coordinator::Write::Events::CoordinationTaskSubmittedV1.new(
      task_id: task_id,
      tool_name: "change_set_create",
      command_id: target_command.command_id,
      canonical_input_digest: Coordinator::Write::CommandInputDigest.new.call(target_command),
      command_input: Coordinator::Write::CommandInputDigest.new.document(target_command),
      submitted_at: "2026-08-28T10:00:00.000000Z",
      ttl_ms: nil,
      poll_interval_ms: 500
    )
  end

  def started_event
    Coordinator::Write::Events::CoordinationTaskExecutionStartedV1.new(
      task_id:,
      started_at: "2026-08-28T10:00:01.000000Z"
    )
  end

  def completed_event(data:, next_actions:)
    structured_content = Coordinator::Write::Tasks::StructuredContentV1.new(
      status: "ok",
      summary: "Completed",
      command_id: target_command.command_id,
      receipt: target_command.command_id,
      context_token: nil,
      data:,
      warnings: [],
      next_actions:
    )
    Coordinator::Write::Events::CoordinationTaskCompletedV1.new(
      task_id:,
      result: Coordinator::Write::Tasks::ToolResultV1.new(
        content: [
          Coordinator::Write::Tasks::TextContentV1.new(
            type: "text",
            text: JSON.generate(structured_content.to_h)
          )
        ],
        is_error: false,
        structured_content:
      ),
      completed_at: "2026-08-28T10:00:02.000000Z"
    )
  end

  def target_command
    @target_command ||= Coordinator::Write::Commands::CreateChangeSet.new(
      command_id: "cmd-terminal-schema",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "schema-agent"),
      change_set_id: "CS-terminal-schema",
      goal: "Validate terminal Task schemas",
      acceptance_criteria: [ "Originating tool and result agree" ]
    )
  end

  def change_set_receipt
    Coordinator::Write::CommandReceiptData::ChangeSet.new(change_set_id: target_command.change_set_id)
  end

  def task_id
    "01919191-9191-7191-8191-919191919191"
  end
end
