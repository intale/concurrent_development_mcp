# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactScopeChangedV1 < Base
      contract type: "DevelopmentArtifactScopeChanged", version: 1

      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :scope, Types::DevelopmentArtifactScope
    end
  end
end
