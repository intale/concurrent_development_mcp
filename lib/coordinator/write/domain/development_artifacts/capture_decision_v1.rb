# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class CaptureDecisionV1 < Value
        Capture = Events::DevelopmentArtifactCapturedV1 | Events::DevelopmentArtifactCapturedV2

        attribute :capture, Capture
        attribute :observation, Events::DevelopmentArtifactObservedV1
        attribute :event_plan, EventPlan.optional
        attribute :outcome, Types::String.enum("captured", "observed", "existing")
      end
    end
  end
end
