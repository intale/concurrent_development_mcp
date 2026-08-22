# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class CommandReceipts
      def initialize(schema_registry: Coordinator::Write::EventSchemaRegistry.new)
        @schema_registry = schema_registry
      end

      def fetch(command_id)
        record = Coordinator::Read::CommandReceipt.find_by(command_id:)
        return unless record

        @schema_registry.load(
          type: "CommandCompleted",
          schema_version: 1,
          data: record.completion
        )
      end

      def store(event:, completion:)
        Coordinator::Read::CommandReceipt.create!(
          command_id: completion.command_id,
          command_stream_revision: event.stream_revision,
          tool_name: completion.tool_name,
          canonical_input_digest: completion.canonical_input_digest,
          status: completion.status,
          summary: completion.summary,
          receipt: completion.receipt,
          completion: completion.to_h,
          completed_at_domain: completion.completed_at
        )
      end
    end
  end
end
