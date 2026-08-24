# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class CompensationRequestFactV1 < Value
      attribute :payload, Events::ReleaseSetCompensationRequestedV1
      attribute :event, EventReference
    end
  end
end
