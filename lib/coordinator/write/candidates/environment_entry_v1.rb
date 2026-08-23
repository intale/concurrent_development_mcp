# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class EnvironmentEntryV1 < Value
      attribute :name, Types::CandidateEnvironmentName
      attribute :value, Types::CandidateEnvironmentValue
    end
  end
end
