# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class OperationBatchMigrationContextV1 < Value
      attribute :source_creation, LegacyEvents::OperationBatchCreatedV1
      attribute :source_creation_event, Types.Instance(PgEventstore::Event)
      attribute :target_stream, StreamReference
      attribute :batch_id, Types::OperationBatchId
      attribute :items, Types::Array.of(OperationBatchItemMigrationV1)

      def item(index)
        items.find { _1.index == index }
      end

      def markers
        [ "operation-batch:#{batch_id}" ]
      end

      def item_markers(index)
        markers + [ "batch-item:#{batch_id}:#{index}" ]
      end
    end
  end
end
