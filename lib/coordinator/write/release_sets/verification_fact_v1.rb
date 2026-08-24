# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class VerificationFactV1 < Value
      attribute :payload, Events::ReleaseSetVerificationRecordedV1
      attribute :event, EventReference
    end
  end
end
