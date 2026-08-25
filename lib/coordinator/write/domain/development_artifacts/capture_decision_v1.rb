# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class CaptureDecisionV1 < Value
        attribute :capture, Events::DevelopmentArtifactCapturedV1
        attribute :event_plan, EventPlan.optional
        attribute :outcome, Types::String.enum("captured", "existing")
      end
    end
  end
end
