# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationAddedToChangeSetV1 < Base
      contract type: "VerificationObligationAddedToChangeSet", version: 1

      attribute :obligation_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
    end
  end
end
