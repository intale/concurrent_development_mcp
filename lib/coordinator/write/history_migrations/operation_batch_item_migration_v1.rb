# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class OperationBatchItemMigrationV1 < Value
      attribute :source_item, OperationBatches::ItemV1
      attribute :target_item, OperationBatches::ItemV2
      attribute :target_command_stream, StreamReference
      attribute :source_completion_event, Types.Instance(PgEventstore::Event).optional
      attribute :encoded_byte_size, Types::OperationBatchEncodedByteSize

      def index
        target_item.index
      end

      def command_id
        target_item.command_id
      end

      def request_id
        target_item.request_id
      end

      def canonical_input_digest
        target_item.canonical_input_digest
      end

      def submitted_input
        target_item.submitted_input
      end

      def actor
        source_actor = target_item.command_input.input.actor
        Commands::Actor.new(
          kind: source_actor.actor_kind,
          id: source_actor.actor_id
        )
      end
    end
  end
end
