# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class CandidateImpacts
      OUTGOING_MATCH_SQL = <<~SQL.squish.freeze
        EXISTS (
          SELECT 1
          FROM candidate_changed_resources subject_changes
          INNER JOIN candidate_changed_resources counterpart_changes
            ON counterpart_changes.repository_id = subject_changes.repository_id
           AND counterpart_changes.path = subject_changes.path
          WHERE subject_changes.candidate_id = :subject_id
            AND counterpart_changes.candidate_id = candidates.candidate_id
        ) OR EXISTS (
          SELECT 1
          FROM candidate_changed_resources subject_changes
          INNER JOIN candidate_observed_inputs counterpart_inputs
            ON counterpart_inputs.repository_id = subject_changes.repository_id
           AND counterpart_inputs.path = subject_changes.path
          WHERE subject_changes.candidate_id = :subject_id
            AND counterpart_inputs.candidate_id = candidates.candidate_id
        ) OR EXISTS (
          SELECT 1
          FROM candidate_impact_keys subject_keys
          INNER JOIN candidate_impact_keys counterpart_keys
            ON counterpart_keys.impact_key = subject_keys.impact_key
          WHERE subject_keys.candidate_id = :subject_id
            AND subject_keys.direction IN ('produces', 'may_affect')
            AND counterpart_keys.candidate_id = candidates.candidate_id
            AND counterpart_keys.direction IN ('consumes', 'assumes')
        )
      SQL
      INCOMING_MATCH_SQL = <<~SQL.squish.freeze
        EXISTS (
          SELECT 1
          FROM candidate_changed_resources counterpart_changes
          INNER JOIN candidate_changed_resources subject_changes
            ON subject_changes.repository_id = counterpart_changes.repository_id
           AND subject_changes.path = counterpart_changes.path
          WHERE counterpart_changes.candidate_id = candidates.candidate_id
            AND subject_changes.candidate_id = :subject_id
        ) OR EXISTS (
          SELECT 1
          FROM candidate_changed_resources counterpart_changes
          INNER JOIN candidate_observed_inputs subject_inputs
            ON subject_inputs.repository_id = counterpart_changes.repository_id
           AND subject_inputs.path = counterpart_changes.path
          WHERE counterpart_changes.candidate_id = candidates.candidate_id
            AND subject_inputs.candidate_id = :subject_id
        ) OR EXISTS (
          SELECT 1
          FROM candidate_impact_keys counterpart_keys
          INNER JOIN candidate_impact_keys subject_keys
            ON subject_keys.impact_key = counterpart_keys.impact_key
          WHERE counterpart_keys.candidate_id = candidates.candidate_id
            AND counterpart_keys.direction IN ('produces', 'may_affect')
            AND subject_keys.candidate_id = :subject_id
            AND subject_keys.direction IN ('consumes', 'assumes')
        )
      SQL
      MATCH_SQL = {
        "incoming" => INCOMING_MATCH_SQL,
        "outgoing" => OUTGOING_MATCH_SQL
      }.freeze
      SOURCE_KEY_DIRECTIONS = %w[produces may_affect].freeze
      TARGET_KEY_DIRECTIONS = %w[consumes assumes].freeze

      def initialize(candidates: Candidates.new)
        @candidates = candidates
      end

      def store_manifest(manifest:)
        record = candidate!(manifest.candidate_id, "manifest resources")
        replace_partition(
          Coordinator::Read::CandidateChangedResource,
          record:,
          values: changed_paths(manifest.files),
          value_key: :path
        )
      end

      def store_build_context(build_context:)
        record = candidate!(build_context.candidate_id, "build-context inputs")
        replace_partition(
          Coordinator::Read::CandidateObservedInput,
          record:,
          values: build_context.inputs.map(&:path).uniq.sort,
          value_key: :path
        )
      end

      def store_surface(event:, surface:)
        record = candidate!(surface.candidate_id, "impact surface")
        verify_surface!(record, surface)
        record.update!(
          impact_surface: surface_document(surface),
          impact_event: event_reference(event).to_h,
          impact_actor: actor(event).to_h,
          impact_markers: event.markers,
          impact_metadata: event.metadata,
          impact_causation_id: event.causation_id,
          impact_correlation_id: event.correlation_id,
          impact_global_position: event.global_position,
          impact_at_domain: surface.derived_at,
          impact_at_store: event.created_at
        )
        replace_impact_keys(record:, surface:)
        record
      end

      def page(query)
        subject = Coordinator::Read::Candidate.find_by(candidate_id: query.candidate_id)
        return unless subject

        relation = matched_candidates(subject:, direction: query.direction)
        if query.after_global_position
          relation = relation.where("submitted_global_position > ?", query.after_global_position)
        end
        records = relation.order(:submitted_global_position).page(1).per(query.limit + 1).to_a
        has_more = records.length > query.limit
        counterparts = records.first(query.limit)
        all_records = [ subject, *counterparts ]
        evidence = indexed_evidence(all_records.map(&:candidate_id))
        summaries = @candidates.summaries(all_records.map(&:candidate_id))
        relationships = counterparts.map do |counterpart|
          build_relationship(
            direction: query.direction,
            subject:,
            counterpart:,
            evidence:,
            summary: summaries.fetch(counterpart.candidate_id)
          )
        end

        CandidateImpactPageV1.new(
          candidate: summaries.fetch(subject.candidate_id),
          impact_surface: impact_surface_view(subject),
          direction: query.direction,
          relationships:,
          next_global_position: has_more ? relationships.last.counterpart.submitted.global_position : nil,
          has_more:
        )
      end

      private

      def candidate!(candidate_id, component)
        Coordinator::Read::Candidate.find_by(candidate_id:) ||
          raise(ProjectionStateError, "CandidateSubmitted must be projected before its #{component}")
      end

      def replace_partition(model, record:, values:, value_key:)
        model.where(candidate_id: record.candidate_id).delete_all
        return if values.empty?

        now = Time.now.utc
        model.insert_all!(values.map do |value|
          {
            candidate_id: record.candidate_id,
            change_set_id: record.change_set_id,
            repository_id: record.repository_id,
            value_key => value,
            created_at: now,
            updated_at: now
          }
        end)
      end

      def replace_impact_keys(record:, surface:)
        Coordinator::Read::CandidateImpactKey.where(candidate_id: record.candidate_id).delete_all
        rows = {
          "produces" => surface.produces,
          "consumes" => surface.consumes,
          "may_affect" => surface.may_affect,
          "assumes" => surface.assumes
        }.flat_map do |direction, entries|
          entries.map do |entry|
            {
              candidate_id: record.candidate_id,
              change_set_id: record.change_set_id,
              direction:,
              impact_key: entry.impact_key
            }
          end
        end
        return if rows.empty?

        now = Time.now.utc
        Coordinator::Read::CandidateImpactKey.insert_all!(rows.map do |row|
          row.merge(created_at: now, updated_at: now)
        end)
      end

      def changed_paths(files)
        files.flat_map do |file|
          case file.status
          when "added", "copied" then [ file.new_path ]
          when "renamed" then [ file.old_path, file.new_path ]
          else [ file.old_path ]
          end
        end.compact.uniq.sort
      end

      def verify_surface!(record, surface)
        matches = record.change_set_id == surface.change_set_id &&
                  record.work_item_id == surface.work_item_id &&
                  record.attempt_id == surface.attempt_id &&
                  record.repository_id == surface.repository_id &&
                  record.target_branch == surface.target_branch &&
                  record.object_format == surface.object_format &&
                  record.head_commit_oid == surface.head_commit_oid &&
                  record.manifest_digest == surface.manifest_digest &&
                  record.build_context_digest == surface.build_context_digest
        return if matches

        raise ProjectionStateError, "Candidate impact-surface identity changed"
      end

      def surface_document(surface)
        {
          policy_version: surface.policy_version,
          surface_digest: surface.surface_digest,
          evidence_revision: surface.evidence_revision,
          manifest_digest: surface.manifest_digest,
          build_context_digest: surface.build_context_digest,
          produces: surface.produces.map(&:to_h),
          consumes: surface.consumes.map(&:to_h),
          may_affect: surface.may_affect.map(&:to_h),
          assumes: surface.assumes.map(&:to_h),
          analyzer: surface.analyzer.to_h,
          evidence_status: surface.evidence_status
        }
      end

      def matched_candidates(subject:, direction:)
        Coordinator::Read::Candidate
          .where(change_set_id: subject.change_set_id)
          .where.not(candidate_id: subject.candidate_id)
          .where(MATCH_SQL.fetch(direction), subject_id: subject.candidate_id)
      end

      def indexed_evidence(candidate_ids)
        changed = grouped_values(
          Coordinator::Read::CandidateChangedResource.where(candidate_id: candidate_ids),
          :path
        )
        inputs = grouped_values(
          Coordinator::Read::CandidateObservedInput.where(candidate_id: candidate_ids),
          :path
        )
        keys = Hash.new { |candidate_hash, candidate_id| candidate_hash[candidate_id] = {} }
        Coordinator::Read::CandidateImpactKey
          .where(candidate_id: candidate_ids)
          .pluck(:candidate_id, :direction, :impact_key)
          .each do |candidate_id, direction, impact_key|
            keys[candidate_id][direction] ||= []
            keys[candidate_id][direction] << impact_key
          end
        { changed:, inputs:, keys: }
      end

      def grouped_values(relation, value_key)
        relation.pluck(:candidate_id, value_key).each_with_object({}) do |(candidate_id, value), result|
          result[candidate_id] ||= []
          result[candidate_id] << value
        end
      end

      def build_relationship(direction:, subject:, counterpart:, evidence:, summary:)
        source, target = direction == "outgoing" ? [ subject, counterpart ] : [ counterpart, subject ]
        reasons = []
        append_path_reason(reasons, source:, target:, evidence:, kind: "changed_resource_overlap")
        append_path_reason(reasons, source:, target:, evidence:, kind: "observed_input_changed")
        append_semantic_reason(reasons, source:, target:, evidence:)
        CandidateImpactRelationshipV1.new(
          counterpart: summary,
          relationship_kind: "potentially_affects",
          reasons:
        )
      end

      def append_path_reason(reasons, source:, target:, evidence:, kind:)
        return unless source.repository_id == target.repository_id

        source_paths = evidence.fetch(:changed).fetch(source.candidate_id, [])
        target_key = kind == "changed_resource_overlap" ? :changed : :inputs
        matches = source_paths.intersection(evidence.fetch(target_key).fetch(target.candidate_id, [])).sort
        return if matches.empty?

        reasons << CandidateImpactReasonV1.new(
          kind:,
          matches:,
          source_evidence: source_evidence(source, :manifest),
          target_evidence: source_evidence(
            target,
            kind == "changed_resource_overlap" ? :manifest : :build_context
          )
        )
      end

      def append_semantic_reason(reasons, source:, target:, evidence:)
        source_keys = keys_for(evidence, source.candidate_id, SOURCE_KEY_DIRECTIONS)
        target_keys = keys_for(evidence, target.candidate_id, TARGET_KEY_DIRECTIONS)
        matches = source_keys.intersection(target_keys).sort
        return if matches.empty?

        reasons << CandidateImpactReasonV1.new(
          kind: "semantic_key_match",
          matches:,
          source_evidence: source_evidence(source, :impact),
          target_evidence: source_evidence(target, :impact)
        )
      end

      def keys_for(evidence, candidate_id, directions)
        direction_map = evidence.fetch(:keys).fetch(candidate_id, {})
        directions.flat_map { direction_map.fetch(_1, []) }.uniq
      end

      def impact_surface_view(record)
        return unless record.impact_surface && record.impact_event

        surface = symbolize(record.impact_surface)
        CandidateImpactSurfaceViewV1.new(
          policy_version: surface.fetch(:policy_version),
          surface_digest: surface.fetch(:surface_digest),
          evidence_revision: surface.fetch(:evidence_revision),
          manifest_digest: surface.fetch(:manifest_digest),
          build_context_digest: surface[:build_context_digest],
          produces: surface.fetch(:produces).map do |entry|
            Coordinator::Write::Candidates::ImpactTransitionV1.new(entry)
          end,
          consumes: surface.fetch(:consumes).map do |entry|
            Coordinator::Write::Candidates::ImpactObservationV1.new(entry)
          end,
          may_affect: surface.fetch(:may_affect).map do |entry|
            Coordinator::Write::Candidates::ImpactKeyV1.new(entry)
          end,
          assumes: surface.fetch(:assumes).map do |entry|
            Coordinator::Write::Candidates::ImpactAssumptionV1.new(entry)
          end,
          analyzer: Coordinator::Write::Candidates::ImpactAnalyzerV1.new(surface.fetch(:analyzer)),
          evidence_status: surface.fetch(:evidence_status),
          evidence: source_evidence(record, :impact)
        )
      end

      def source_evidence(record, prefix)
        event = record.public_send("#{prefix}_event")
        actor_value = record.public_send("#{prefix}_actor")
        raise ProjectionStateError, "Candidate #{prefix} evidence is incomplete" unless event && actor_value

        CandidateSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(event)),
          actor: AttributedActorV1.new(symbolize(actor_value)),
          markers: record.public_send("#{prefix}_markers"),
          metadata: record.public_send("#{prefix}_metadata"),
          global_position: record.public_send("#{prefix}_global_position"),
          occurred_at: record.public_send("#{prefix}_at_domain").utc.iso8601(6),
          persisted_at: record.public_send("#{prefix}_at_store").utc.iso8601(6),
          causation_id: record.public_send("#{prefix}_causation_id"),
          correlation_id: record.public_send("#{prefix}_correlation_id")
        )
      end

      def actor(event)
        AttributedActorV1.new(
          kind: event.metadata.fetch("actor_kind"),
          id: event.metadata.fetch("actor_id"),
          authenticated: false
        )
      end

      def event_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array then value.map { symbolize(_1) }
        else value
        end
      end
    end
  end
end
