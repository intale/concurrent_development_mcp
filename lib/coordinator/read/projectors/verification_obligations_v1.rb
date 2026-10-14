# frozen_string_literal: true

module Coordinator::Read::Projectors
  class VerificationObligationsV1
    def initialize(source_loader:)
      @source_loader = source_loader
    end

    def call(events)
      enriched = events.select { _1.type == "VerificationObligationCreated" || Coordinator::Read::VerificationObligations::SourceLoader::TERMINAL_TYPES.include?(_1.type) }
      definitions = enriched.map { _1.data.fetch("obligation_id") }.uniq.to_h { [ _1, @source_loader.definition(_1) ] }
      outcomes = enriched.reject { _1.type == "VerificationObligationCreated" }.uniq(&:id).to_h do |event|
        [ event.id, @source_loader.outcome(event, definition: definitions.fetch(event.data.fetch("obligation_id"))) ]
      end
      model = Coordinator::Read::VerificationObligation
      model.connection_pool.with_connection do |connection|
        connection.transaction do
          obligations = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :obligation_id ])
          evidence_items = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :evidence_id ])
          fold = Coordinator::Read::Projections::VerificationObligations.new(obligations:, evidence_items:)
          events.each { fold.apply(_1, definition: definitions[_1.data.fetch("obligation_id")], outcome: outcomes[_1.id]) }
          [ [ model, obligations ], [ Coordinator::Read::VerificationObligationEvidenceItem, evidence_items ] ].each do |table, patches|
            Coordinator::Read::Repositories::BatchWriter.new(model: table, patches:).call
          end
        end
      end
      nil
    end
  end
end
