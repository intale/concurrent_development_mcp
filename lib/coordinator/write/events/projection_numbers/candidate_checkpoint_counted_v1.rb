# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class CandidateCheckpointCountedV1 < Coordinator::Write::Events::Base
    contract type: "CandidateCheckpointCounted", version: 1

    attribute :statistics_id, Coordinator::Write::Types::UuidV7
    attribute :candidate_id, Coordinator::Write::Types::Identifier
  end
end
