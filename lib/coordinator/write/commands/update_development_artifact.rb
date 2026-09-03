# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class UpdateDevelopmentArtifact < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :expected_revision, Types::Integer.constrained(gteq: 0)
      attribute :changes, DevelopmentArtifacts::UpdateChangesV1
    end
  end
end
