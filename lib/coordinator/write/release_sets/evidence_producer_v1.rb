# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class EvidenceProducerV1 < Value
      attribute :name, Types::String.constrained(min_size: 1, max_size: 100)
      attribute :version, Types::String.constrained(min_size: 1, max_size: 100)
    end
  end
end
