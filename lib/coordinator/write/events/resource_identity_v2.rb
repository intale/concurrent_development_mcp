# frozen_string_literal: true

module Coordinator::Write
  module Events
    module ResourceIdentityV2
      class Registered < Base
        contract type: "ResourceRegistered", version: 2

        attribute :resource_id, Types::ResourceId
        attribute :repository_id, Types::RepositoryId
        attribute :kind, Types::ResourceKind
        attribute :normalized_path, Types::ResourcePath
      end

      class Bound < Base
        contract type: "ResourceBound", version: 2

        attribute :resource_id, Types::ResourceId
        attribute :repository_id, Types::RepositoryId
        attribute :kind, Types::ResourceKind
        attribute :normalized_path, Types::ResourcePath
      end

      class Unbound < Base
        contract type: "ResourceUnbound", version: 2

        attribute :resource_id, Types::ResourceId
        attribute :repository_id, Types::RepositoryId
        attribute :kind, Types::ResourceKind
        attribute :normalized_path, Types::ResourcePath
        attribute :reason, Types::String.constrained(max_size: 2_000)
      end

      Registration = Types.Instance(Registered)
      Binding = Types.Instance(Bound)
      Unbinding = Types.Instance(Unbound)
      CurrentBinding = Binding | Unbinding
      ResolutionEvent = Registration | Binding
      Event = ResolutionEvent | Unbinding
    end
  end
end
