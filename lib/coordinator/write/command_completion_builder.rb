# frozen_string_literal: true

module Coordinator::Write
  class CommandCompletionBuilder
    def initialize(
      persisted_events_contract: Contracts::PersistedEvents.new
    )
      @persisted_events_contract = persisted_events_contract
    end

    def create_change_set(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "change_set_create",
        summary: "ChangeSet created.",
        data: CommandReceiptData::ChangeSet.new(change_set_id: command.change_set_id),
        next_actions: [
          NextAction.new(
            tool: "work_item_create",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def work_item_create(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "work_item_create",
        summary: "WorkItem created.",
        data: CommandReceiptData::WorkItem.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id
        ),
        next_actions: [
          NextAction.new(
            tool: "work_item_create",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          ),
          NextAction.new(
            tool: "change_set_activate",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def work_item_dependency_declare(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "work_item_dependency_declare",
        summary: "WorkItem dependency declared.",
        data: CommandReceiptData::Dependency.new(
          change_set_id: command.change_set_id,
          dependency_id: command.dependency_id
        ),
        next_actions: [
          NextAction.new(
            tool: "change_set_activate",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def change_set_activate(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "change_set_activate",
        summary: "ChangeSet activated.",
        data: CommandReceiptData::ChangeSet.new(change_set_id: command.change_set_id),
        next_actions: [
          NextAction.new(
            tool: "coord_context",
            arguments: NextAction::ChangeSetArguments.new(change_set_id: command.change_set_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def work_item_acquire(command:, input_digest:, persisted_events:, completed_at:)
      attempt_arguments = NextAction::AttemptArguments.new(
        change_set_id: command.change_set_id,
        work_item_id: command.work_item_id,
        attempt_id: command.attempt_id
      )

      build_completion(
        command:,
        tool_name: "work_item_acquire",
        summary: "WorkItem acquired and Attempt started.",
        data: CommandReceiptData::Attempt.new(attempt_arguments.to_h),
        next_actions: [ NextAction.new(tool: "write_set_reserve", arguments: attempt_arguments) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def write_set_reserve(command:, reservation:, input_digest:, persisted_events:, completed_at:)
      attempt_arguments = NextAction::AttemptArguments.new(
        change_set_id: command.change_set_id,
        work_item_id: command.work_item_id,
        attempt_id: command.attempt_id
      )

      build_completion(
        command:,
        tool_name: "write_set_reserve",
        summary: "Write set reserved.",
        data: CommandReceiptData::LeaseSet.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: command.repository_id,
          lease_set_id: reservation.lease_set_id,
          policy_version: reservation.policy_version,
          acquired_at: reservation.reserved_at,
          expires_at: reservation.expires_at,
          resources: reservation.resources
        ),
        next_actions: [ NextAction.new(tool: "coord_context", arguments: attempt_arguments) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def write_set_expand(command:, expansion:, input_digest:, persisted_events:, completed_at:)
      attempt_arguments = NextAction::AttemptArguments.new(
        change_set_id: command.change_set_id,
        work_item_id: command.work_item_id,
        attempt_id: command.attempt_id
      )

      build_completion(
        command:,
        tool_name: "write_set_expand",
        summary: "Write set expanded.",
        data: CommandReceiptData::LeaseSetExpansion.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: command.repository_id,
          lease_set_id: expansion.lease_set_id,
          policy_version: expansion.policy_version,
          expanded_at: expansion.expanded_at,
          expires_at: expansion.expires_at,
          added_resources: expansion.added_resources,
          resource_count: expansion.resource_count
        ),
        next_actions: [ NextAction.new(tool: "coord_context", arguments: attempt_arguments) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def lease_renew(command:, renewal:, input_digest:, persisted_events:, completed_at:)
      attempt_arguments = NextAction::AttemptArguments.new(
        change_set_id: command.change_set_id,
        work_item_id: command.work_item_id,
        attempt_id: command.attempt_id
      )

      build_completion(
        command:,
        tool_name: "lease_renew",
        summary: "Lease set renewed.",
        data: CommandReceiptData::LeaseSetRenewal.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: renewal.repository_id,
          lease_set_id: renewal.lease_set_id,
          policy_version: renewal.policy_version,
          resources: renewal.resources,
          resource_count: renewal.resource_count,
          renewed_at: renewal.renewed_at,
          previous_expires_at: renewal.previous_expires_at,
          expires_at: renewal.expires_at
        ),
        next_actions: [ NextAction.new(tool: "coord_context", arguments: attempt_arguments) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def lease_release(command:, release:, input_digest:, persisted_events:, completed_at:)
      attempt_arguments = NextAction::AttemptArguments.new(
        change_set_id: command.change_set_id,
        work_item_id: command.work_item_id,
        attempt_id: command.attempt_id
      )

      build_completion(
        command:,
        tool_name: "lease_release",
        summary: "Lease set released.",
        data: CommandReceiptData::LeaseSetRelease.new(
          change_set_id: command.change_set_id,
          work_item_id: command.work_item_id,
          attempt_id: command.attempt_id,
          repository_id: release.repository_id,
          lease_set_id: release.lease_set_id,
          policy_version: release.policy_version,
          resources: release.resources,
          resource_count: release.resource_count,
          previous_expires_at: release.previous_expires_at,
          released_at: release.released_at
        ),
        next_actions: [ NextAction.new(tool: "coord_context", arguments: attempt_arguments) ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def lease_expire_policy(command:, expiration:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "lease_expire_policy",
        summary: "Resource lease explicitly expired.",
        data: CommandReceiptData::ResourceLeaseExpiry.new(
          resource_key_hash: expiration.resource_key_hash,
          lease_id: expiration.lease_id,
          lease_set_id: expiration.lease_set_id,
          fencing_token: expiration.fencing_token,
          expires_at: expiration.expires_at,
          expired_at: expiration.expired_at
        ),
        next_actions: [],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def guidance_record(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "guidance_record",
        summary: "Guidance evidence recorded without activating policy.",
        data: CommandReceiptData::Guidance.new(
          message_id: command.message_id,
          conversation_id: command.conversation_id,
          source: command.source,
          policy_status: "evidence_only",
          recorded_at: completed_at
        ),
        next_actions: [
          NextAction.new(
            tool: "guidance_get",
            arguments: NextAction::GuidanceArguments.new(message_id: command.message_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def decision_interpretation_propose(command:, proposal:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "decision_interpretation_propose",
        summary: "Atomic decision interpretation proposed without activating policy.",
        data: CommandReceiptData::InterpretationProposal.new(
          interpretation_id: command.interpretation_id,
          source_message_id: command.source_message_id,
          assessment: proposal.assessment,
          proposed_at: proposal.proposed_at
        ),
        next_actions: [
          NextAction.new(
            tool: "decision_interpretation_list",
            arguments: NextAction::InterpretationListArguments.new(
              message_id: command.source_message_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def decision_interpretation_adjudicate(command:, slot:, input_digest:, persisted_events:, completed_at:)
      outcome = {
        "accept" => "accepted_for_activation",
        "reject" => "rejected",
        "request_clarification" => "clarification_required"
      }.fetch(command.action)
      build_completion(
        command:,
        tool_name: "decision_interpretation_adjudicate",
        summary: "Interpretation adjudication recorded without activating policy.",
        data: CommandReceiptData::InterpretationAdjudication.new(
          interpretation_id: command.interpretation_id,
          source_message_id: command.source_message_id,
          action: command.action,
          outcome:,
          policy_status: "proposal_only",
          slot: command.action == "accept" ? slot : nil,
          adjudicated_at: completed_at
        ),
        next_actions: [
          NextAction.new(
            tool: "decision_interpretation_list",
            arguments: NextAction::InterpretationListArguments.new(
              message_id: command.source_message_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def decision_activate(command:, activation:, partitions:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "decision_activate",
        summary: "Accepted interpretation activated as authoritative policy.",
        data: CommandReceiptData::DecisionActivation.new(
          decision_id: command.decision_id,
          interpretation_id: command.interpretation_id,
          outcome: "activated",
          policy_status: "active",
          definition_digest: activation.definition_digest,
          slot: activation.slot,
          partitions:,
          activated_at: activation.activated_at
        ),
        next_actions: [
          NextAction.new(
            tool: "decision_get",
            arguments: NextAction::DecisionArguments.new(decision_id: command.decision_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    def decision_correct(
      command:,
      correction:,
      correction_event:,
      partitions:,
      input_digest:,
      persisted_events:,
      completed_at:
    )
      build_completion(
        command:,
        tool_name: "decision_correct",
        summary: "Active Decision definition corrected from accepted interpretation evidence.",
        data: CommandReceiptData::DecisionCorrection.new(
          decision_id: command.decision_id,
          interpretation_id: command.interpretation_id,
          outcome: "corrected",
          policy_status: "active",
          previous_definition_digest: correction.previous_definition_digest,
          definition_digest: correction.definition.digest,
          correction_event:,
          slot: correction.slot,
          partitions:,
          corrected_at: correction.corrected_at
        ),
        next_actions: [
          NextAction.new(
            tool: "decision_get",
            arguments: NextAction::DecisionArguments.new(decision_id: command.decision_id)
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    private

    def build_completion(command:, tool_name:, summary:, data:, next_actions:, input_digest:, persisted_events:, completed_at:)
      events = apply_persisted_events_contract(persisted_events)
      emitted_events = events.map { event_reference(_1) }

      Events::CommandCompletedV1.new(
        command_id: command.command_id,
        tool_name:,
        canonical_input_digest: input_digest,
        status: "ok",
        summary:,
        receipt: command.command_id,
        data:,
        warnings: [],
        next_actions:,
        emitted_events:,
        completed_at:
      )
    end

    def apply_persisted_events_contract(events)
      result = @persisted_events_contract.call(events:)
      return result.to_h.fetch(:events) if result.success?

      raise ArgumentError, "persisted_events violate their dry-rb contract: #{result.errors.to_h.inspect}"
    end

    def event_reference(event)
      EventReference.new(
        event_id: event.id,
        type: event.type,
        stream_context: event.stream.context,
        stream_name: event.stream.stream_name,
        stream_id: event.stream.stream_id,
        stream_revision: event.stream_revision
      )
    end
  end
end
