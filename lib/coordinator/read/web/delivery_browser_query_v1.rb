# frozen_string_literal: true

module Coordinator::Read::Web
  class DeliveryBrowserQueryV1
    Sort = Coordinator::Shared::Types::String.enum("oldest_first", "newest_first")

    class Catalog < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :sort, Sort
      attribute :candidate_change_set_id, Coordinator::Shared::Types::Identifier.optional
      attribute :candidate_checkpoint_kind, Coordinator::Shared::Types::CandidateCheckpointKind.optional
      attribute :candidate_after_position, Coordinator::Shared::Types::GlobalPosition.optional
      attribute :candidate_after_id, Coordinator::Shared::Types::Identifier.optional
      attribute :obligation_change_set_id, Coordinator::Shared::Types::Identifier.optional
      attribute :obligation_status, Coordinator::Shared::Types::VerificationObligationStatus.optional
      attribute :obligation_after_position, Coordinator::Shared::Types::GlobalPosition.optional
      attribute :obligation_after_id, Coordinator::Shared::Types::Identifier.optional
      attribute :merge_after_position, Coordinator::Shared::Types::GlobalPosition.optional
      attribute :merge_after_id, Coordinator::Shared::Types::Identifier.optional
      attribute :release_change_set_id, Coordinator::Shared::Types::Identifier.optional
      attribute :release_status, Coordinator::Shared::Types::String.optional
      attribute :release_after_position, Coordinator::Shared::Types::GlobalPosition.optional
      attribute :release_after_id, Coordinator::Shared::Types::Identifier.optional
    end

    class Candidate < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :candidate_id, Coordinator::Shared::Types::Identifier
      attribute :direction, Coordinator::Shared::Types::CandidateImpactQueryDirection
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :after_impact_position, Coordinator::Shared::Types::GlobalPosition.optional
    end

    class Verification < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :obligation_id, Coordinator::Shared::Types::Identifier
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :after_evidence_position, Coordinator::Shared::Types::GlobalPosition.optional
      attribute :after_evidence_id, Coordinator::Shared::Types::UuidV7.optional
    end

    class Merge < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :merge_snapshot_id, Coordinator::Shared::Types::Identifier
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :after_authorization_position, Coordinator::Shared::Types::GlobalPosition.optional
      attribute :after_authorization_id, Coordinator::Shared::Types::UuidV7.optional
    end

    class Release < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :release_set_id, Coordinator::Shared::Types::Identifier
    end

    class Batches < Coordinator::Shared::Value
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 50)
      attribute :sort, Sort
      attribute :target_tool, Coordinator::Shared::Types::OperationBatchTargetTool.optional
      attribute :status, Coordinator::Shared::Types::OperationBatchStatus.optional
      attribute :after_position, Coordinator::Shared::Types::GlobalPosition.optional
      attribute :after_id, Coordinator::Shared::Types::UuidV7.optional
    end

    class Batch < Coordinator::Shared::Value
      attribute :batch_id, Coordinator::Shared::Types::UuidV7
      attribute :first, Coordinator::Shared::Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :after_index, Coordinator::Shared::Types::OperationBatchItemIndex.optional
    end
  end
end
