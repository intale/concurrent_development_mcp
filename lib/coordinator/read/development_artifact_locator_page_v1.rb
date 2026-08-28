# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactLocatorPageV1 < Value
    class Cursor < Value
      attribute :after_observed_sequence, Types::Integer.constrained(gteq: 0)
      attribute :through_observed_sequence, Types::Integer.constrained(gteq: 0).optional
      attribute :after_current_global_position, Types::GlobalPosition.optional
      attribute :after_observation_id, Types::DevelopmentArtifactObservationId.optional
    end

    attribute :resolution, Types::String.enum("absent", "unique", "ambiguous")
    attribute :items,
              Types::Array.of(DevelopmentArtifactSummaryV1).constrained(
                max_size: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
              )
    attribute :continuation_cursor, Cursor
    attribute :has_more, Types::Bool
  end
end
