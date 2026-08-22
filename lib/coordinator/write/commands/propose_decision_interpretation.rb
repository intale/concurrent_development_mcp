# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ProposeDecisionInterpretation < Value
      Ambiguity = Interpretations::InterpretationAmbiguityV1

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :source_span, Interpretations::SourceSpanV1.optional
      attribute :classifier, Interpretations::ClassifierAttributionV1
      attribute :proposed_decision, Interpretations::SubmittedDecisionV1
      attribute :ambiguities, Types::Array.of(Ambiguity).constrained(max_size: 20)
    end
  end
end
