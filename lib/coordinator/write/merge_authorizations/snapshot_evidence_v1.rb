# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class SnapshotEvidenceV1 < Value
      attribute :registration, MergeSnapshots::StateV2
      attribute :registration_event, EventReference
      attribute :verification, MergeSnapshotVerifications::VerifiedObservationV2.optional
      attribute :verification_event, EventReference.optional
    end
  end
end
