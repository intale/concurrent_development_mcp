# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class AgentChoiceInvalidationV2 < EventMetadata
      attribute :previous_context_digest, Types::Sha256Digest
      attribute :resulting_context_digest, Types::Sha256Digest
    end
  end
end
