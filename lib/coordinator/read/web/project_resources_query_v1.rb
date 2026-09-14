# frozen_string_literal: true

module Coordinator::Read::Web
  class ProjectResourcesQueryV1
    class Collection < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :kind, Coordinator::Shared::Types::String.enum("resources", "active_work_intentions")
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :after_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :sort,
                Coordinator::Shared::Types::String.default("newest_first".freeze).enum("newest_first", "oldest_first")
      attribute :as_of, Coordinator::Shared::Types::Timestamp
      attribute :path, Coordinator::Shared::Types::String.optional
      attribute :resource_kind,
                Coordinator::Shared::Types::String.enum("file", "directory").optional
      attribute :resource_lifecycle_status,
                Coordinator::Shared::Types::String.enum("registered", "current", "inactive").optional
      attribute :agent_id, Coordinator::Shared::Types::String.optional
      attribute :change_set_id, Coordinator::Shared::Types::String.optional
      attribute :work_item_id, Coordinator::Shared::Types::String.optional
      attribute :attempt_id, Coordinator::Shared::Types::String.optional
      attribute :mode, Coordinator::Shared::Types::WorkIntentionMode.optional
    end

    class Detail < Coordinator::Shared::Value
      attribute :project_ref, Coordinator::Shared::Types::String
      attribute :scope, Coordinator::Shared::Types::String
      attribute :kind, Coordinator::Shared::Types::String.enum("resource", "work_intention")
      attribute :id, Coordinator::Shared::Types::UuidV7
      attribute :as_of, Coordinator::Shared::Types::Timestamp
    end
  end
end
