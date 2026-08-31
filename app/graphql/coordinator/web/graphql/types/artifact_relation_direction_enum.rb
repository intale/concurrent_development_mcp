# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ArtifactRelationDirectionEnum < BaseEnum
    graphql_name "ArtifactRelationDirection"

    value "INCOMING", value: "incoming"
    value "OUTGOING", value: "outgoing"
    value "BOTH", value: "both"
  end
end
