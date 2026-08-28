# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactRelationshipCapacityV1 < Value
    attribute :active_count, Types::Integer.constrained(gteq: 0)
    attribute :active_limit, Types::Integer.constrained(gteq: 1)
    attribute :active_remaining, Types::Integer.constrained(gteq: 0)
    attribute :lifetime_count, Types::Integer.constrained(gteq: 0)
    attribute :lifetime_limit, Types::Integer.constrained(gteq: 1)
    attribute :lifetime_remaining, Types::Integer.constrained(gteq: 0)
  end
end
