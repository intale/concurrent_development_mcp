# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class GitObjectIds < Dry::Validation::Contract
      params do
        required(:commit_oids).array(:string)
      end

      rule(:commit_oids).each do
        key.failure("must be 40 or 64 lowercase hexadecimal characters") unless Types::GIT_OID_PATTERN.match?(value)
      end
    end
  end
end
