# frozen_string_literal: true

module Coordinator::Write
  class RepositoryMarkerBuilder
    def initialize(compound_marker_builder: CompoundMarkerBuilder.new)
      @compound_marker_builder = compound_marker_builder
    end

    def call(registration)
      scope = "scope:#{registration.scope}"
      repository = "repository:#{registration.repository_id}"
      identity = @compound_marker_builder.call(
        CompoundMarkerDefinitionV1.new(
          purpose: "scoped-repository",
          components: [ scope, repository ]
        )
      )

      [ scope, repository, identity.marker ]
    end
  end
end
