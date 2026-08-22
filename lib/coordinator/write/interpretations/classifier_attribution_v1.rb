# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class ClassifierAttributionV1 < Value
      attribute :id, Types::Identifier
      attribute :version, Types::InterpretationLabel
      attribute :ontology_version, Types::Integer.constrained(eql: 1)
      attribute :confidence_millionths, Types::ClassifierConfidenceMillionths
    end
  end
end
