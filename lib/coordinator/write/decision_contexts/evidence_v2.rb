# frozen_string_literal: true

module Coordinator::Write
  module DecisionContexts
    class EvidenceV2 < Value
      attribute :document, ContextDocumentV1
    end
  end
end
