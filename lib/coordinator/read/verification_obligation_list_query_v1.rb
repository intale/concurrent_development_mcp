# frozen_string_literal: true

module Coordinator::Read
  class VerificationObligationListQueryV1 < Value
    attribute :change_set_id, Types::Identifier.optional
    attribute :candidate_id, Types::Identifier.optional
    attribute :work_item_id, Types::Identifier.optional
    attribute :repository_id, Types::RepositoryId.optional
    attribute :kind, Types::VerificationObligationKind.optional
    attribute :enforcement, Types::String.enum("verification_gate", "merge_gate").optional
    attribute :status, Types::VerificationObligationStatus
    attribute :after_global_position, Types::GlobalPosition.optional
    attribute :limit, Types::Integer.constrained(gteq: 1, lteq: 100)
  end
end
