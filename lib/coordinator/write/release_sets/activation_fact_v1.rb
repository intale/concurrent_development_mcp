# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class ActivationFactV1 < Value
      attribute :payload, Events::ReleaseSetActivatedV1
      attribute :event, EventReference
    end
  end
end
