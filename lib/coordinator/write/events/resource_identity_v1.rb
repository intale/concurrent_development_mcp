# frozen_string_literal: true

module Coordinator::Write
  module Events
    module ResourceIdentityV1
      class Registered < Base
        contract type: "ResourceRegistered", version: 1

        attribute :resource_id, Types::ResourceId
        attribute :repository_id, Types::RepositoryId
        attribute :kind, Types::ResourceKind
        attribute :normalized_path, Types::ResourcePath
        attribute :registered_at, Types::Timestamp
      end

      class Bound < Base
        contract type: "ResourceBound", version: 1

        attribute :resource_id, Types::ResourceId
        attribute :repository_id, Types::RepositoryId
        attribute :kind, Types::ResourceKind
        attribute :normalized_path, Types::ResourcePath
        attribute :bound_at, Types::Timestamp
      end

      Registration = Types.Instance(Registered)
      Binding = Types.Instance(Bound)
      Event = Registration | Binding
    end
  end
end
