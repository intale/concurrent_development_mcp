# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class RegistrationV1 < Value
      attribute :payload, Events::CommandRegisteredV1
      attribute :canonical_input_digest, Types::Sha256Digest
    end
  end
end
