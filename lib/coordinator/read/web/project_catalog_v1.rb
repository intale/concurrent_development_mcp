# frozen_string_literal: true

module Coordinator::Read::Web
  class ProjectCatalogV1
    class RepositoryMember < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :display_name, Coordinator::Shared::Types::String.optional
      attribute :paths,
                Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::String).constrained(max_size: 20)
      attribute :remotes,
                Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::String).constrained(max_size: 20)
      attribute :registered_at, Coordinator::Shared::Types::Timestamp
    end

    class RepositoryPage < Coordinator::Shared::Value
      attribute :items,
                Coordinator::Shared::Types::Array.of(RepositoryMember).constrained(max_size: 100)
      attribute :next_repository_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
      attribute :total_count, Coordinator::Shared::Types::Integer.constrained(gteq: 1)
    end

    class ProjectSummary < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :display_label, Coordinator::Shared::Types::String
      attribute :repository_count, Coordinator::Shared::Types::Integer.constrained(gteq: 1)
      attribute :repositories, RepositoryPage
    end

    class ProjectPage < Coordinator::Shared::Value
      attribute :items,
                Coordinator::Shared::Types::Array.of(ProjectSummary).constrained(max_size: 100)
      attribute :next_scope, Coordinator::Shared::Types::String.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class ProjectOverview < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :display_label, Coordinator::Shared::Types::String
      attribute :repository_count, Coordinator::Shared::Types::Integer.constrained(gteq: 1)
      attribute :repositories, RepositoryPage
    end
  end
end
