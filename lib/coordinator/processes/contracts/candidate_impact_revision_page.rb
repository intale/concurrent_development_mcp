# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class CandidateImpactRevisionPage < Dry::Validation::Contract
      params do
        required(:page).value(Types.Instance(CandidateObligations::RevisionPageV1))
        required(:stream_id).filled(:string)
        required(:from_revision).value(Types::StreamRevision)
        required(:to_revision).value(Types::StreamRevision)
        required(:page_size).value(Types::CandidateImpactScanPageSize)
      end

      rule(:page, :stream_id, :from_revision, :to_revision, :page_size) do
        page = values[:page]
        registrations = page.registrations
        revisions = registrations.map(&:stream_revision)
        ordered = revisions.each_cons(2).all? { _1 < _2 }
        bounded = revisions.all? { _1.between?(values[:from_revision], values[:to_revision]) }
        envelopes = registrations.all? do |event|
          event.type == "CandidateImpactSurfaceRegistered" &&
            event.stream.context == "DevelopmentIntegration" &&
            event.stream.stream_name == "CandidateImpactRegistry" &&
            event.stream.stream_id == values[:stream_id]
        end
        cursor = page.last_processed_revision == revisions.last
        cardinality = registrations.length <= values[:page_size] &&
                      (!page.has_more || registrations.length == values[:page_size])
        valid = ordered && bounded && envelopes && cursor && cardinality
        key(:page).failure("must be one exact ascending bounded registry page") unless valid
      end
    end
  end
end
