# frozen_string_literal: true

module Coordinator::Read::Web
  class ProjectCatalogQueriesV1
    class Discovery < Coordinator::Shared::Value
      attribute :search, Coordinator::Shared::Types::String.optional
      attribute :sort, Coordinator::Shared::Types::String.enum("oldest_first", "newest_first")
      attribute :after_scope, Coordinator::Shared::Types::String.optional
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :repositories_first,
                Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 20)
    end

    class Overview < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :after_repository_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :repositories_first,
                Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
    end
  end
end
