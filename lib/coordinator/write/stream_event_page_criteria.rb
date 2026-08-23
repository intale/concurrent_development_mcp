# frozen_string_literal: true

module Coordinator::Write
  class StreamEventPageCriteria < Value
    attribute :event_type, Types::Identifier
    attribute :from_revision, Types::StreamRevision
    attribute :to_revision, Types::StreamRevision
    attribute :page_size, Types::CandidateImpactScanPageSize
    attribute :direction, Types::Symbol.enum(:asc, :desc)

    def query_max_count
      page_size + 1
    end
  end
end
