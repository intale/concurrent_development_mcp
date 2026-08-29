# frozen_string_literal: true

module Coordinator::Write
  class ResourceIdentityV1 < Value
    UnbindingReason = Types::String.enum("removed", "renamed", "type_changed")

    attribute :repository_id, Types::UuidV7
    attribute :kind, Types::ResourceKind
    attribute :normalized_path, Types::ResourcePath
    attribute :identity_marker, Types::ResourceMarker
    attribute :current_path_marker, Types::ResourceMarker
  end
end
