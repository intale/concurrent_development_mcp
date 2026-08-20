# frozen_string_literal: true

module Coordinator
  class CommandCompletionBuilder
    def initialize(
      canonical_json: CanonicalJson.new,
      persisted_events_contract: Contracts::PersistedEvents.new
    )
      @canonical_json = canonical_json
      @persisted_events_contract = persisted_events_contract
    end

    def create_change_set(command:, input_digest:, persisted_events:, completed_at:)
      build_completion(
        command:,
        tool_name: "change_set_create",
        summary: "ChangeSet created.",
        data: CommandReceiptData::ChangeSet.new(change_set_id: command.change_set_id),
        scope: ContextTokenDocument::ChangeSetScope.new(change_set_id: command.change_set_id),
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
        scope: ContextTokenDocument::WorkItemScope.new(
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
        scope: ContextTokenDocument::ChangeSetScope.new(change_set_id: command.change_set_id),
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
        scope: ContextTokenDocument::ChangeSetScope.new(change_set_id: command.change_set_id),
        next_actions: [
          NextAction.new(
            tool: "coord_context",
            arguments: NextAction::ContextArguments.new(
              change_set_id: command.change_set_id,
              after_command_id: command.command_id
            )
          )
        ],
        input_digest:,
        persisted_events:,
        completed_at:
      )
    end

    private

    def build_completion(command:, tool_name:, summary:, data:, scope:, next_actions:, input_digest:, persisted_events:, completed_at:)
      events = apply_persisted_events_contract(persisted_events)
      emitted_events = events.map { event_reference(_1) }
      projection_barriers = coord_context_barriers(events)
      token_document = ContextTokenDocument.new(
        schema: "context-token/v1",
        scope:,
        projection_barriers:
      )

      Events::CommandCompletedV1.new(
        command_id: command.command_id,
        tool_name:,
        canonical_input_digest: input_digest,
        status: "ok",
        summary:,
        receipt: command.command_id,
        context_token: @canonical_json.sha256(token_document.to_h),
        data:,
        warnings: [],
        next_actions:,
        emitted_events:,
        projection_barriers:,
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

    def coord_context_barriers(events)
      latest_by_stream = events.each_with_object({}) do |event, result|
        key = event.stream.to_a
        previous = result[key]
        result[key] = event if previous.nil? || event.stream_revision > previous.stream_revision
      end

      ProjectionBarriers.new(
        coord_context_v1: latest_by_stream.values.map do |event|
          ProjectionBarrier.new(
            stream_context: event.stream.context,
            stream_name: event.stream.stream_name,
            stream_id: event.stream.stream_id,
            stream_revision: event.stream_revision
          )
        end.sort_by { |barrier| [ barrier.stream_context, barrier.stream_name, barrier.stream_id ] }
      )
    end
  end
end
