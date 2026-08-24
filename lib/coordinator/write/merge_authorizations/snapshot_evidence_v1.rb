# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class SnapshotEvidenceV1 < Value
      attribute :registration, Events::MergeSnapshotRegisteredV1
      attribute :registration_event, EventReference
      attribute :verification, Events::MergeSnapshotVerifiedV1.optional
      attribute :verification_event, EventReference.optional
    end
  end
end
