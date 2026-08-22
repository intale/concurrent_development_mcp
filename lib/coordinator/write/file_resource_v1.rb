# frozen_string_literal: true

module Coordinator::Write
  class FileResourceV1 < Value
    attribute :kind, Types::ResourceKind
    attribute :path, Types::ResourcePath
    attribute :base_blob_oid, Types::GitOid.optional
    attribute :resource_key, Types::String
    attribute :resource_key_hash, Types::Sha256Digest
    attribute :policy_version, Types::String.enum(ResourceKeyDocumentV1::POLICY_VERSION)
  end
end
