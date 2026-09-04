# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetVerificationRecordedV2 < Base
      contract type: "ReleaseSetVerificationRecorded", version: 2

      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :attempt_number, Types::ReleaseSetVerificationAttemptNumber
      attribute :evidence, ReleaseSets::VerificationEvidenceV2
    end
  end
end
