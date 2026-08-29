# frozen_string_literal: true

module Coordinator::Read
  class ResourceViewV1 < Value
    attribute :resource_id, Types::ResourceId
    attribute :repository_id, Types::RepositoryId
    attribute :kind, Types::ResourceKind
    attribute :normalized_path, Types::ResourcePath
    attribute :lifecycle_status, Types::String.enum("registered", "current", "inactive")
    attribute :unbinding_reason, Coordinator::Write::ResourceIdentityV1::UnbindingReason.optional
    attribute :registered, ResourceSourceEvidenceV1.optional
    attribute :latest_transition, ResourceSourceEvidenceV1.optional
  end
end
