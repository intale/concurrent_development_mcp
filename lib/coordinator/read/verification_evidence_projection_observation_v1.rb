# frozen_string_literal: true

module Coordinator::Read
  class VerificationEvidenceProjectionObservationV1 < Value
    attribute :submission, Types.Instance(Coordinator::Write::Events::VerificationEvidenceSubmittedV1)
    attribute :event, Coordinator::Write::EventReference
  end
end
