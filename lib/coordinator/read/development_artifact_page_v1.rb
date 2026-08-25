# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactPageV1 < Value
    attribute :items,
              Types::Array.of(DevelopmentArtifactSummaryV1).constrained(
                max_size: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
              )
    attribute :next_global_position, Types::GlobalPosition.optional
    attribute :has_more, Types::Bool
  end
end
