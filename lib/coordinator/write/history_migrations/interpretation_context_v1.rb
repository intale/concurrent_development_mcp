# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class InterpretationContextV1 < Value
      attribute :source_proposal, Events::DecisionInterpretationProposedV1
      attribute :source_proposal_event, Types.Instance(PgEventstore::Event)
      attribute :target_stream, StreamReference
      attribute :interpretation_id, Types::UuidV7
      attribute :source_message_id, Types::UuidV7
      attribute :source_text, Types::GuidanceText
    end
  end
end
