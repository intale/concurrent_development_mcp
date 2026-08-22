# frozen_string_literal: true

module Coordinator::Read
  class ProjectionDefinition < Value
    attribute :name, Types::Identifier
    attribute :version, Types::Integer.constrained(gteq: 1)
  end
end
