# frozen_string_literal: true

module Coordinator::Read
  module DecisionResolution
    class ContextV1 < Value
      attribute :document, ContextDocumentV1
      attribute :digest, Types::Sha256Digest
      attribute :resolved_at, Types::Timestamp
    end
  end
end
