# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetCompensationRequestedV2 < Base
      contract type: "ReleaseSetCompensationRequested", version: 2

      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :reason, Types::ReleaseSetEvidenceSummary
      attribute :trigger_kind, Types::ReleaseSetCompensationTriggerKind
    end
  end
end
