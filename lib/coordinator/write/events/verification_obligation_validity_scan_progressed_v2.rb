# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationValidityScanProgressedV2 < Base
      contract type: "VerificationObligationValidityScanProgressed", version: 2

      attribute :scan_id, Types::UuidV7
      attribute :page_number, Types::Integer.constrained(gteq: 1)
      attribute :next_from_position, Types::GlobalPosition
      attribute :change_set_id, Types::Identifier
      attribute :page_size, Types::VerificationObligationValidityPageSize
    end
  end
end
