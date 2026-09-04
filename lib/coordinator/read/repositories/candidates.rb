# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class Candidates
      def fetch(candidate_id)
        record = Coordinator::Read::Candidate.find_by(candidate_id:)
        record && build_view(record)
      end

      def store_submission(candidate:)
        submitted_event = candidate.submitted_event
        manifest_event = candidate.manifest_event
        build_context_event = candidate.build_context_event
        Coordinator::Read::Candidate.create!(
          candidate_id: candidate.candidate_id,
          change_set_id: candidate.change_set_id,
          work_item_id: candidate.work_item_id,
          attempt_id: candidate.attempt_id,
          agent_id: candidate.agent_id,
          repository_id: candidate.repository_id,
          target_branch: candidate.target_branch,
          object_format: candidate.object_format,
          base_commit_oid: candidate.base_commit_oid,
          head_commit_oid: candidate.head_commit_oid,
          checkpoint_kind: candidate.checkpoint_kind,
          lease_set_id: candidate.intention_set_id,
          lease_policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
          lease_references: candidate.lease_references.map(&:to_h),
          manifest_digest: candidate.manifest_digest,
          build_context_digest: candidate.build_context_digest,
          evidence_status: candidate.evidence_status,
          **source_columns(:submitted, submitted_event),
          manifest: {
            policy_version: manifest_event.metadata.fetch("policy_version"),
            digest: manifest_event.metadata.fetch("manifest_digest"),
            files: candidate.manifest.files.map(&:to_h),
            collector: manifest_event.metadata.fetch("collector")
          },
          **source_columns(:manifest, manifest_event),
          build_context: build_context_document(candidate),
          **optional_source_columns(:build_context, build_context_event)
        )
      end

      def page(query)
        relation = Coordinator::Read::Candidate.where(attempt_id: query.attempt_id)
        if query.after_global_position
          relation = relation.where("submitted_global_position > ?", query.after_global_position)
        end
        rows = relation.order(:submitted_global_position).page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        items = rows.first(query.limit).map { build_summary(_1) }

        CandidatePageV1.new(
          attempt_id: query.attempt_id,
          items:,
          next_global_position: has_more ? items.last.submitted.global_position : nil,
          has_more:
        )
      end

      def summaries(candidate_ids)
        Coordinator::Read::Candidate.where(candidate_id: candidate_ids).to_h do |record|
          [ record.candidate_id, build_summary(record) ]
        end
      end

      private

      def build_context_document(candidate)
        context = candidate.build_context
        event = candidate.build_context_event
        return unless context && event

        {
          policy_version: event.metadata.fetch("policy_version"),
          digest: event.metadata.fetch("build_context_digest"),
          inputs: context.inputs.map(&:to_h),
          environment: context.environment.map(&:to_h),
          dependency_graph_digest: event.metadata["dependency_graph_digest"],
          test_environment_digest: event.metadata["test_environment_digest"],
          collector: event.metadata.fetch("collector")
        }
      end

      def source_columns(prefix, event)
        {
          "#{prefix}_event": event_reference(event).to_h,
          "#{prefix}_actor": actor(event).to_h,
          "#{prefix}_markers": event.markers,
          "#{prefix}_metadata": event.metadata,
          "#{prefix}_causation_id": event.causation_id,
          "#{prefix}_correlation_id": event.correlation_id,
          "#{prefix}_global_position": event.global_position,
          "#{prefix}_at_domain": event.created_at,
          "#{prefix}_at_store": event.created_at
        }
      end

      def optional_source_columns(prefix, event)
        return {} unless event

        source_columns(prefix, event)
      end

      def build_view(record)
        CandidateViewV1.new(
          candidate_id: record.candidate_id,
          change_set_id: record.change_set_id,
          work_item_id: record.work_item_id,
          attempt_id: record.attempt_id,
          agent_id: record.agent_id,
          repository_id: record.repository_id,
          target_branch: record.target_branch,
          object_format: record.object_format,
          base_commit_oid: record.base_commit_oid,
          head_commit_oid: record.head_commit_oid,
          checkpoint_kind: record.checkpoint_kind,
          lease_set_id: record.lease_set_id,
          lease_policy_version: record.lease_policy_version,
          lease_references: record.lease_references.map do |reference|
            Coordinator::Write::LeaseReferenceV2.new(symbolize(reference))
          end,
          manifest_digest: record.manifest_digest,
          build_context_digest: record.build_context_digest,
          evidence_status: record.evidence_status,
          submitted: source_evidence(record, :submitted),
          manifest: manifest_view(record),
          build_context: build_context_view(record)
        )
      end

      def build_summary(record)
        CandidateSummaryV1.new(
          candidate_id: record.candidate_id,
          change_set_id: record.change_set_id,
          work_item_id: record.work_item_id,
          attempt_id: record.attempt_id,
          repository_id: record.repository_id,
          target_branch: record.target_branch,
          object_format: record.object_format,
          base_commit_oid: record.base_commit_oid,
          head_commit_oid: record.head_commit_oid,
          checkpoint_kind: record.checkpoint_kind,
          manifest_digest: record.manifest_digest,
          build_context_digest: record.build_context_digest,
          evidence_status: record.evidence_status,
          manifest_observed: record.manifest.present?,
          build_context_observed: record.build_context.present?,
          submitted: source_evidence(record, :submitted)
        )
      end

      def manifest_view(record)
        return unless record.manifest && record.manifest_event

        manifest = symbolize(record.manifest)
        CandidateManifestViewV1.new(
          policy_version: manifest.fetch(:policy_version),
          digest: manifest.fetch(:digest),
          files: manifest.fetch(:files).map do |file|
            Coordinator::Write::Candidates::ManifestFileV1.new(file)
          end,
          collector: Coordinator::Write::Candidates::EvidenceCollectorV1.new(
            manifest.fetch(:collector)
          ),
          evidence: source_evidence(record, :manifest)
        )
      end

      def build_context_view(record)
        return unless record.build_context && record.build_context_event

        context = symbolize(record.build_context)
        CandidateBuildContextViewV1.new(
          policy_version: context.fetch(:policy_version),
          digest: context.fetch(:digest),
          inputs: context.fetch(:inputs).map do |input|
            Coordinator::Write::Candidates::BuildInputV1.new(input)
          end,
          environment: context.fetch(:environment).map do |entry|
            Coordinator::Write::Candidates::EnvironmentEntryV1.new(entry)
          end,
          dependency_graph_digest: context[:dependency_graph_digest],
          test_environment_digest: context[:test_environment_digest],
          collector: Coordinator::Write::Candidates::EvidenceCollectorV1.new(
            context.fetch(:collector)
          ),
          evidence: source_evidence(record, :build_context)
        )
      end

      def source_evidence(record, prefix)
        CandidateSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.public_send("#{prefix}_event"))),
          actor: AttributedActorV1.new(symbolize(record.public_send("#{prefix}_actor"))),
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
