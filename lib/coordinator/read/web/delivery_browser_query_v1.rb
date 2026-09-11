# frozen_string_literal: true

module Coordinator::Read::Web
  class DeliveryBrowserQueryV1
    Sort = Coordinator::Shared::Types::String.enum("oldest_first", "newest_first")

    class Candidates < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :sort, Sort
      attribute :change_set_id, Coordinator::Shared::Types::Identifier.optional
      attribute :checkpoint_kind, Coordinator::Shared::Types::CandidateCheckpointKind.optional
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :after_id, Coordinator::Shared::Types::Identifier.optional
    end

    class Obligations < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :sort, Sort
      attribute :change_set_id, Coordinator::Shared::Types::Identifier.optional
      attribute :status, Coordinator::Shared::Types::VerificationObligationStatus.optional
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :after_id, Coordinator::Shared::Types::Identifier.optional
    end

    class Merges < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :sort, Sort
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :after_id, Coordinator::Shared::Types::Identifier.optional
    end

    class Releases < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :sort, Sort
      attribute :change_set_id, Coordinator::Shared::Types::Identifier.optional
      attribute :status, Coordinator::Shared::Types::String.optional
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :after_id, Coordinator::Shared::Types::Identifier.optional
    end

    class Candidate < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :candidate_id, Coordinator::Shared::Types::Identifier
      attribute :direction, Coordinator::Shared::Types::CandidateImpactQueryDirection
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :after_impact_position, Coordinator::Shared::Types::GlobalPosition.optional
    end

    class Verification < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :obligation_id, Coordinator::Shared::Types::Identifier
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :after_evidence_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :after_evidence_id, Coordinator::Shared::Types::UuidV7.optional
    end

    class Merge < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :merge_snapshot_id, Coordinator::Shared::Types::Identifier
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :after_authorization_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :after_authorization_id, Coordinator::Shared::Types::UuidV7.optional
    end

    class Release < Coordinator::Shared::Value
      attribute :project_scope, Coordinator::Shared::Types::String
      attribute :release_set_id, Coordinator::Shared::Types::Identifier
    end

    class Batches < Coordinator::Shared::Value
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :sort, Sort
      attribute :target_tool, Coordinator::Shared::Types::OperationBatchTargetTool.optional
      attribute :status, Coordinator::Shared::Types::OperationBatchStatus.optional
      attribute :after_updated_at, Coordinator::Shared::Types::Timestamp.optional
      attribute :after_id, Coordinator::Shared::Types::UuidV7.optional
    end

    class Batch < Coordinator::Shared::Value
      attribute :batch_id, Coordinator::Shared::Types::UuidV7
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :after_index, Coordinator::Shared::Types::OperationBatchItemIndex.optional
    end
  end
end
