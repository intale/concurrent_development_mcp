# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class AgentChoiceAcceptanceV2 < EventMetadata
      attribute :context_digest, Types::Sha256Digest
    end
  end
end
