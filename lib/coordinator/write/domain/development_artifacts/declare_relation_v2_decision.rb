# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class DeclareRelationV2Decision < Value
        attribute :relation_id, Types::DevelopmentArtifactRelationId
        attribute :source_artifact_id, Types::DevelopmentArtifactId
        attribute :event_plan, EventPlan.optional
        attribute :outcome, Types::String.enum("declared", "existing", "superseded")
      end
    end
  end
end
