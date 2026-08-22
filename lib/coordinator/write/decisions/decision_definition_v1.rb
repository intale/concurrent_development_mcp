# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionDefinitionV1 < Value
      attribute :document, DecisionDefinitionDocumentV1
      attribute :digest, Types::Sha256Digest
    end
  end
end
