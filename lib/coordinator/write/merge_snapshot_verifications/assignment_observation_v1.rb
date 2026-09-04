# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class AssignmentObservationV1 < Value
      attribute :assignment, Events::MergeSnapshotVerificationAssignedV1
      attribute :event, EventReference
    end
  end
end
