# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class EvidenceObservationV1 < Value
      attribute :submission, Types.Instance(Events::MergeSnapshotVerificationSubmittedV1)
      attribute :event, EventReference
    end
  end
end
