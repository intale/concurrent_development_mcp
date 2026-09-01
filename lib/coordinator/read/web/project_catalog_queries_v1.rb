# frozen_string_literal: true

module Coordinator::Read::Web
  class ProjectCatalogQueriesV1
    class Discovery < Coordinator::Shared::Value
      attribute :search, Coordinator::Shared::Types::String.optional
      attribute :sort, Coordinator::Shared::Types::String.enum("scope_asc", "scope_desc")
      attribute :after_scope, Coordinator::Shared::Types::String.optional
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :repositories_first,
                Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 20)
    end

    class Overview < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :after_repository_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :repositories_first,
                Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
    end
  end
end
