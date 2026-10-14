# frozen_string_literal: true

module Coordinator::Read::Projectors
  class OperationBatchesV2
    def call(events)
      model = Coordinator::Read::OperationBatch
      model.connection_pool.with_connection do |connection|
        connection.transaction do
          headers = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :batch_id ])
          items = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :batch_id, :item_index ])
          outcomes = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :batch_id, :item_index ])
          fold = Coordinator::Read::Projections::OperationBatches.new(headers:, items:, outcomes:, item_sources: item_sources(events))
          events.each { fold.apply(_1) }
          [ [ model, headers ], [ Coordinator::Read::OperationBatchItem, items ],
            [ Coordinator::Read::OperationBatchOutcome, outcomes ] ].each do |table, patches|
            Coordinator::Read::Repositories::BatchWriter.new(model: table, patches:).call
          end
        end
      end
      nil
    end

    private

    def item_sources(events)
      pairs = events.select { Coordinator::Read::Projections::OperationBatches::OUTCOMES.key?(_1.type) }
        .map { [ _1.data.fetch("batch_id"), _1.data.fetch("index") ] }.uniq
      return {} if pairs.empty?

      Coordinator::Read::OperationBatchItem.where([ :batch_id, :item_index ] => pairs)
        .pluck(:batch_id, :item_index, :command_id, :canonical_input_digest).to_h do |batch, index, command, digest|
          [ [ batch, index ], { command_id: command, canonical_input_digest: digest } ]
        end
    end
  end
end
