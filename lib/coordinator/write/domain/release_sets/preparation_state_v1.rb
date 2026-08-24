# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class PreparationStateV1 < Value
        Member = Types.Instance(Coordinator::Write::ReleaseSets::MemberEvidenceV1)

        attribute :existing_preparation, EventReference.optional
        attribute :ordered_members,
                  Types::Array.of(Member)
                    .constrained(
                      min_size: Types::RELEASE_SET_MINIMUM_MEMBERS,
                      max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS
                    )
      end
    end
  end
end
