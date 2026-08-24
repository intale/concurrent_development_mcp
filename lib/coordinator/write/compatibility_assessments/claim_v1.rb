# frozen_string_literal: true

module Coordinator::Write
  module CompatibilityAssessments
    class ClaimV1 < Value
      attribute :claim_id, Types::UuidV7
      attribute :fencing_token, Types::FencingToken
    end
  end
end
