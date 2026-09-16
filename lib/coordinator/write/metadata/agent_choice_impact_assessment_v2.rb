# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class AgentChoiceImpactAssessmentV2 < EventMetadata
      attribute :before_context_digest, Types::Sha256Digest
      attribute :after_context_digest, Types::Sha256Digest
    end
  end
end
