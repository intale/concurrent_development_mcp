# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ResourceKindEnum < BaseEnum
    graphql_name "ResourceKind"

    value "DIRECTORY", value: "directory"
    value "FILE", value: "file"
  end
end
