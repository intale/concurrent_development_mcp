# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class RelationDecisionV1 < Value
        attribute :declaration, Events::DevelopmentArtifactRelationDeclaredV1
        attribute :event_plan, EventPlan.optional
        attribute :outcome, Types::String.enum("declared", "existing")
      end
    end
  end
end
