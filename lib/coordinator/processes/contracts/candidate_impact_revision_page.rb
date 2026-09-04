# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class CandidateImpactRevisionPage < Dry::Validation::Contract
      params do
        required(:page).value(Types.Instance(CandidateObligations::RevisionPageV1))
        required(:change_set_id).filled(:string)
        required(:from_revision).value(Types::StreamRevision)
        required(:to_revision).value(Types::StreamRevision)
        required(:page_size).value(Types::CandidateImpactScanPageSize)
      end

      rule(:page, :change_set_id, :from_revision, :to_revision, :page_size) do
        page = values[:page]
        registrations = page.registrations
        revisions = registrations.map(&:global_position)
        ordered = revisions.each_cons(2).all? { _1 < _2 }
        bounded = revisions.all? { _1.between?(values[:from_revision], values[:to_revision]) }
        envelopes = registrations.all? do |event|
          event.type == "CandidateImpactSurfaceAssigned" &&
            event.stream.context == "DevelopmentIntegration" &&
            event.stream.stream_name == "Candidate" &&
            event.markers.include?("change-set:#{values[:change_set_id]}")
        end
        cursor = if page.last_processed_revision
          page.last_processed_revision.between?(values[:from_revision], values[:to_revision]) &&
            revisions.all? { _1 <= page.last_processed_revision }
        else
          revisions.empty? && !page.has_more
        end
        cardinality = registrations.length <= values[:page_size] &&
                      (!page.has_more || page.last_processed_revision)
        valid = ordered && bounded && envelopes && cursor && cardinality
        key(:page).failure("must be one exact ascending bounded registry page") unless valid
      end
    end
  end
end
