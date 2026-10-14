# frozen_string_literal: true

module Coordinator::Read::Projectors
  class DecisionGovernanceV1
    def initialize(source_loader:)
      @source_loader = source_loader
    end

    def call(events)
      sources = events.uniq(&:id).to_h { [ _1.id, @source_loader.call(_1) ] }
      model = Coordinator::Read::DecisionDefinition
      model.connection_pool.with_connection do |connection|
        connection.transaction do
          definitions = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :decision_id ])
          slots = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :slot_id ])
          partitions = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :partition_id ])
          fold = Coordinator::Read::Projections::DecisionGovernance.new(definitions:, slots:, partitions:,
            slot_states: load_slots(events), partition_states: load_partitions(events))
          events.each { fold.apply(_1, source: sources.fetch(_1.id)) }
          [ [ model, definitions ], [ Coordinator::Read::DecisionSlotHead, slots ],
            [ Coordinator::Read::DecisionPartitionHead, partitions ] ].each do |table, patches|
            Coordinator::Read::Repositories::BatchWriter.new(model: table, patches:).call
          end
        end
      end
      nil
    end

    private

    def load_slots(events)
      ids = events.select { %w[DecisionSlotOpened DecisionSlotHeadChanged].include?(_1.type) }.map { _1.data.fetch("slot_id") }.uniq
      return {} if ids.empty?

      Coordinator::Read::DecisionSlotHead.where(slot_id: ids).pluck(:slot_id, :decision_id, :slot).to_h do |id, owner, slot|
        [ id, { decision_id: owner, slot: Coordinator::Read::CommandResults::Source.document(slot) } ]
      end
    end

    def load_partitions(events)
      ids = events.select { %w[DecisionAddedToPartition DecisionRemovedFromPartition].include?(_1.type) }
        .map { _1.data.fetch("partition_id") }.uniq
      return {} if ids.empty?

      Coordinator::Read::DecisionPartitionHead.where(partition_id: ids).pluck(:partition_id, :active_decisions).to_h do |id, entries|
        [ id, entries.to_h { [ _1.fetch("decision_id"), Coordinator::Read::CommandResults::Source.document(_1) ] } ]
      end
    end
  end
end
