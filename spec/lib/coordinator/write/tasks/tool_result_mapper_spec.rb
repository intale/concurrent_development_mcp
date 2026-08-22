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
      ],
      [
        :write_set_unchanged,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result"
        },
        Coordinator::Write::Tasks::DomainErrorV1::AttemptError,
        "denied"
      ],
      [
        :lease_set_mismatch,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          current_lease_set_id: "0198e03a-d112-7000-8000-000000000001",
          requested_lease_set_id: "0198e03a-d112-7000-8000-000000000002"
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseSetMismatchError,
        "denied"
      ],
      [
        :resource_evidence_conflict,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          resource_key: "repo:billing:file:app/models/invoice.rb",
          resource_key_hash: "sha256:4ef29088b0a3df37b0bdf49785a9dce3dad97985b7f22d5ab5d86e04cdc4049a",
          current_base_blob_oid: "a" * 40,
          requested_base_blob_oid: "b" * 40
        },
        Coordinator::Write::Tasks::DomainErrorV1::ResourceEvidenceConflictError,
        "denied"
      ],
      [
        :write_set_limit_reached,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          current_resource_count: 31,
          requested_addition_count: 2
        },
        Coordinator::Write::Tasks::DomainErrorV1::WriteSetLimitError,
        "denied"
      ],
      [
        :lease_set_expired,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          resource_key_hash: "sha256:4ef29088b0a3df37b0bdf49785a9dce3dad97985b7f22d5ab5d86e04cdc4049a",
          lease_id: "0198e03a-d112-7000-8000-000000000001",
          fencing_token: 7,
          expires_at: "2026-08-22T10:30:00.000000Z"
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseSetExpiredError,
        "denied"
      ],
      [
        :lease_set_not_current,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          resource_key_hash: "sha256:4ef29088b0a3df37b0bdf49785a9dce3dad97985b7f22d5ab5d86e04cdc4049a",
          expected_lease_id: "0198e03a-d112-7000-8000-000000000001",
          current_lease_id: "0198e03a-d112-7000-8000-000000000002",
          expected_fencing_token: 7,
          current_fencing_token: 8,
          current_lease_set_id: "0198e03a-d112-7000-8000-000000000003",
          current_attempt_id: "ATT-task-result-other",
          current_expires_at: "2026-08-22T10:45:00.000000Z",
          current_released_at: nil,
          current_expired_at: nil
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseSetNotCurrentError,
        "denied"
      ],
      [
        :write_set_released,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          released_at: "2026-08-22T10:40:00.000000Z"
        },
        Coordinator::Write::Tasks::DomainErrorV1::WriteSetReleasedError,
        "denied"
      ],
      [
        :lease_set_snapshot_mismatch,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          current_resource_key_hashes: [ "sha256:#{'a' * 64}" ],
          requested_resource_key_hashes: [ "sha256:#{'b' * 64}" ]
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseSetSnapshotMismatchError,
        "denied"
      ],
      [
        :lease_reference_mismatch,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          resource_key_hash: "sha256:#{'a' * 64}",
          current_lease_id: "0198e03a-d112-7000-8000-000000000001",
          requested_lease_id: "0198e03a-d112-7000-8000-000000000002",
          current_fencing_token: 7,
          requested_fencing_token: 6
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseReferenceMismatchError,
        "denied"
      ],
      [
        :lease_deadline_not_extended,
        {
          change_set_id: "CS-task-result",
          work_item_id: "W-task-result",
          attempt_id: "ATT-task-result",
          current_expires_at: "2026-08-22T10:30:00.000000Z",
          requested_expires_at: "2026-08-22T10:29:00.000000Z"
        },
        Coordinator::Write::Tasks::DomainErrorV1::LeaseDeadlineNotExtendedError,
        "denied"
      ],
      [
        :message_already_recorded,
        { message_id: "M-task-result" },
        Coordinator::Write::Tasks::DomainErrorV1::MessageAlreadyRecordedError,
        "denied"
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
