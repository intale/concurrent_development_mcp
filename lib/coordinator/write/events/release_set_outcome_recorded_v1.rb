# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetOutcomeRecordedV1 < Base
      contract type: "ReleaseSetOutcomeRecorded", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :outcome, Types::ReleaseSetCompletionOutcome
    end
  end
end
