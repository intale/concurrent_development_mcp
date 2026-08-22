# frozen_string_literal: true

RSpec.describe Coordinator::Write::Tasks::ToolResultMapper do
  include Dry::Monads[:result]

  subject(:mapper) { described_class.new }

  it "maps every modeled target denial into a strict persisted domain-error shape" do
    examples = [
      [
        :change_set_already_exists,
        { change_set_id: "CS-task-result" },
        Coordinator::Write::Tasks::DomainErrorV1::ChangeSetError,
        "denied"
      ],
      [
        :dependency_endpoint_missing,
        { change_set_id: "CS-task-result", dependency_id: "DEP-task-result" },
        Coordinator::Write::Tasks::DomainErrorV1::ActivationDependencyError,
        "denied"
      ],
      [
        :work_item_already_exists,
        { change_set_id: "CS-task-result", work_item_id: "W-task-result" },
        Coordinator::Write::Tasks::DomainErrorV1::WorkItemError,
        "denied"
      ],
      [
        :dependency_id_reused,
        {
          change_set_id: "CS-task-result",
          dependency_id: "DEP-task-result",
          producer_work_item_id: "W-task-result-a",
          consumer_work_item_id: "W-task-result-b"
        },
        Coordinator::Write::Tasks::DomainErrorV1::DependencyError,
        "denied"
      ],
      [
        :work_item_unavailable,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result"
        },
        Coordinator::Write::Tasks::DomainErrorV1::AttemptError,
        "conflict"
      ],
      [
        :command_id_reused,
        {
          command_id: "cmd-task-result",
          existing_tool_name: "change_set_create",
          existing_input_digest: "sha256:#{'a' * 64}",
          requested_tool_name: "change_set_create",
          requested_input_digest: "sha256:#{'b' * 64}"
        },
        Coordinator::Write::Tasks::DomainErrorV1::CommandIdReusedError,
        "command_id_reused"
      ],
      [
        :lease_busy,
        {
          resource_key: "repo:billing:file:app/models/invoice.rb",
          resource_key_hash: "sha256:4ef29088b0a3df37b0bdf49785a9dce3dad97985b7f22d5ab5d86e04cdc4049a",
          lease_id: "0198e03a-d112-7000-8000-000000000001",
          owner_attempt_id: "ATT-task-result-owner",
          owner_agent_id: "agent-owner",
          fencing_token: 7,
          expires_at: "2026-08-22T10:30:00.000000Z"
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseBusyError,
        "busy"
      ]
    ]

    examples.each do |code, details, error_class, status|
      error = Coordinator::Write::OutcomeError.new(
        code:,
        message: "The target command was denied",
        details:
      )

      result = mapper.call(Failure(error), command_id: "cmd-task-result")

      expect(result.is_error).to be(true)
      expect(result.structured_content.status).to eq(status)
      expect(result.structured_content.data).to be_a(error_class)
      expect(JSON.parse(result.content.sole.text)).to eq(
        JSON.parse(JSON.generate(result.structured_content.to_h))
      )
    end
  end
end
