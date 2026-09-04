# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationValidityScanSourceLinkedV1 < Base
      contract type: "VerificationObligationValidityScanSourceLinked", version: 1

      attribute :scan_id, Types::UuidV7
      attribute :role, Types::String.enum("superseding_partition")
      attribute :source, EventReference
    end
  end
end
