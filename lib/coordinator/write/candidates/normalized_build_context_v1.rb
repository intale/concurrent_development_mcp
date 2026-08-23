# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class NormalizedBuildContextV1 < Value
      Input = Types.Instance(BuildInputV1)
      Environment = Types.Instance(EnvironmentEntryV1)

      attribute :inputs, Types::Array.of(Input).constrained(max_size: 64)
      attribute :environment, Types::Array.of(Environment).constrained(max_size: 32)
      attribute :dependency_graph_digest, Types::Sha256Digest.optional
      attribute :test_environment_digest, Types::Sha256Digest.optional
      attribute :collector, Types.Instance(EvidenceCollectorV1)
    end
  end
end
