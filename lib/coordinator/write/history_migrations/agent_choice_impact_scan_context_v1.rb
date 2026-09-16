# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class AgentChoiceImpactScanContextV1 < Value
      attribute :target_stream, Types.Instance(StreamReference)
      attribute :scan_id, Types::UuidV7
      attribute :decision_change, AgentChoiceImpacts::DecisionChangeEvidenceV2
      attribute? :from_position, Types::GlobalPosition.optional.default(nil)
      attribute? :to_position, Types::GlobalPosition.optional.default(nil)
      attribute? :page_size, Types::AgentChoiceImpactPageSize.optional.default(nil)
    end
  end
end
