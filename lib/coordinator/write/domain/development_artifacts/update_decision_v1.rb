# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class UpdateDecisionV1 < Value
        attribute :artifact_id, Types::DevelopmentArtifactId
        attribute :event_plan, EventPlan.optional
        attribute :changed_properties, Types::Array.of(Types::String)
        attribute :outcome, Types::String.enum("updated", "existing")
      end
    end
  end
end
