# frozen_string_literal: true

module Coordinator::Write
  class GuidanceAnchorsV1 < Value
    attribute :repository_ids, Types::GuidanceRepositoryIds
    attribute :change_set_id, Types::Identifier.optional
    attribute :work_item_id, Types::Identifier.optional
    attribute :attempt_id, Types::Identifier.optional
  end
end
