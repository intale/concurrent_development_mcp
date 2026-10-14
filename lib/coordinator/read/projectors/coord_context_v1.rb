# frozen_string_literal: true

module Coordinator::Read::Projectors
  class CoordContextV1
    HISTORY_COLUMNS = %i[work_intention_set_id work_intention_set_repository_id work_intention_set_policy_version work_intention_set_intentions
      work_intention_set_declared_at_domain work_intention_set_last_expanded_event work_intention_set_last_expanded_at_domain
      work_intention_set_last_renewed_event work_intention_set_last_renewed_at_domain work_intention_set_previous_expires_at_domain
      work_intention_set_expires_at_domain work_intention_set_withdrawal_event work_intention_set_withdrawn_at_domain work_intention_member_states].freeze
    HISTORY_TIMES = HISTORY_COLUMNS.select { _1.to_s.end_with?("_at_domain") }.freeze

    def initialize(source_loader:)
      @source_loader = source_loader
    end

    def call(events)
      sources = events.filter_map { |event| source = @source_loader.call(event); source && [ event, source ] }
      return if sources.empty?

      ids = sources.map { _1.last.fetch(:change_set_id) }.uniq
      model = Coordinator::Read::CoordContext
      model.connection_pool.with_connection do |connection|
        connection.transaction do
          existing = model.where(change_set_id: ids).pluck(:change_set_id, :document, :source_positions, :repository_checkpoint_numbers)
          documents, positions, checkpoint_numbers = {}, {}, {}
          existing.each do |id, document, source_positions, counts|
            documents[id] = Coordinator::Read::CommandResults::Source.document(document)
            positions[id] = Coordinator::Read::CommandResults::Source.document(source_positions)
            checkpoint_numbers[id] = Coordinator::Read::CommandResults::Source.document(counts)
          end
          contexts = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :change_set_id ])
          histories = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :attempt_id ])
          scopes = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: %i[scope_kind scope_id])
          fold = Coordinator::Read::Projections::CoordContexts.new(contexts:, histories:, scopes:, documents:, positions:, checkpoint_numbers:,
            history_documents: load_history_documents(sources))
          sources.each { |event, source| fold.apply(event, source:) }
          [ [ model, contexts ], [ Coordinator::Read::AttemptHistory, histories ], [ Coordinator::Read::CoordContextScope, scopes ] ].each do |table, patches|
            Coordinator::Read::Repositories::BatchWriter.new(model: table, patches:).call
          end
        end
      end
      nil
    end

    private

    def load_history_documents(sources)
      ids = sources.select { _1.first.type.start_with?("ResourceWorkIntention") }.map { _1.last.fetch(:attempt_id) }.uniq
      return {} if ids.empty?

      Coordinator::Read::AttemptHistory.where(attempt_id: ids).pluck(:attempt_id, *HISTORY_COLUMNS).to_h do |id, *values|
        document = HISTORY_COLUMNS.zip(values).to_h
        HISTORY_TIMES.each { |column| document[column] = document[column]&.utc&.iso8601(6) }
        [ id, Coordinator::Read::CommandResults::Source.document(document) ]
      end
    end
  end
end
