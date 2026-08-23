# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactSurfaceBuilder < Dry::Operation
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(attributes)
        surface = attributes.fetch(:surface)
        produces = surface.fetch(:produces).map do |entry|
          ImpactTransitionV1.new(
            impact_key: entry.fetch(:impact_key),
            before: entry[:before],
            after: entry.fetch(:after)
          )
        end.sort_by { _1.impact_key.b }
        consumes = surface.fetch(:consumes).map { ImpactObservationV1.new(_1) }.sort_by { _1.impact_key.b }
        may_affect = surface.fetch(:may_affect).map { ImpactKeyV1.new(_1) }.sort_by { _1.impact_key.b }
        assumes = surface.fetch(:assumes).map { ImpactAssumptionV1.new(_1) }.sort_by { _1.impact_key.b }
        document = ImpactSurfaceDocumentV1.new(
          schema: ImpactSurfaceDocumentV1::SCHEMA,
          candidate_id: attributes.fetch(:candidate_id),
          repository_id: attributes.fetch(:repository_id),
          head_commit_oid: attributes.fetch(:head_commit_oid),
          manifest_digest: attributes.fetch(:manifest_digest),
          build_context_digest: attributes[:build_context_digest],
          produces:,
          consumes:,
          may_affect:,
          assumes:
        )
        actor = attributes.fetch(:actor)

        ImpactSurfaceV1.new(
          policy_version: ImpactSurfaceDocumentV1::SCHEMA,
          digest: @canonical_json.sha256(document.to_h),
          produces:,
          consumes:,
          may_affect:,
          assumes:,
          analyzer: ImpactAnalyzerV1.new(
            kind: actor.fetch(:kind),
            id: actor.fetch(:id),
            analyzer_version: attributes.fetch(:analyzer_version)
          )
        )
      rescue CanonicalJson::Error => error
        step Failure(
          OutcomeError.new(
            code: :invalid_candidate_impact_evidence,
            message: "Candidate impact evidence cannot be canonically encoded",
            details: { reason: error.message }
          )
        )
      end
    end
  end
end
