# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class BuildContextDocumentV1 < Value
      SCHEMA = "candidate-build-context/v1"
      Input = Types.Instance(BuildInputV1)
      Environment = Types.Instance(EnvironmentEntryV1)

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :candidate_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :object_format, Types::GitObjectFormat
      attribute :head_commit_oid, Types::GitOid
      attribute :inputs, Types::Array.of(Input).constrained(max_size: 64)
      attribute :environment, Types::Array.of(Environment).constrained(max_size: 32)
      attribute :dependency_graph_digest, Types::Sha256Digest.optional
      attribute :test_environment_digest, Types::Sha256Digest.optional
    end
  end
end
