# frozen_string_literal: true

module Coordinator::Read
  class CandidateGetQueryV1 < Value
    attribute :candidate_id, Types::Identifier
  end
end
