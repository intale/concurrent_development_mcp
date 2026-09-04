# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationValidityScanStartedV2 < Base
      contract type: "VerificationObligationValidityScanStarted", version: 2

      attribute :scan_id, Types::UuidV7
      attribute :change_set_id, Types::Identifier
      attribute :from_position, Types::GlobalPosition
      attribute :to_position, Types::GlobalPosition
      attribute :page_size, Types::VerificationObligationValidityPageSize
    end
  end
end
