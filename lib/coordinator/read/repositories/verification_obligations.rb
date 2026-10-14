# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class VerificationObligations
      def page(query)
        observed_at = Time.iso8601(query.observed_at)
        relation = filtered(Coordinator::Read::VerificationObligation.all, query, observed_at:)
        if query.after_global_position
          relation = relation.where("event_global_position > ?", query.after_global_position)
        end
        rows = relation.order(:event_global_position).page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        selected = rows.first(query.limit)
        evidence_by_obligation = evidence_by_obligation(selected.map(&:obligation_id))
        items = selected.map do |record|
          build(
            record,
            observed_at:,
            evidence_records: evidence_by_obligation.fetch(record.obligation_id, [])
          )
        end

        VerificationObligationPageV1.new(
          items:,
          next_global_position: has_more ? items.last.evidence.global_position : nil,
          has_more:,
          observed_at: query.observed_at
        )
      end

      private

      def projected_obligation(record)
        Coordinator::Write::VerificationObligations::DefinitionV2.new(symbolize(record.obligation))
      end

      def creation_reference(record)
        Coordinator::Write::EventReference.new(symbolize(record.event))
      end

      def projected_submission(record)
        Coordinator::Write::Events::VerificationEvidenceSubmittedV2.new(symbolize(record.submission))
      end

      def evidence_by_obligation(obligation_ids)
        Coordinator::Read::VerificationObligationEvidenceItem
          .where(obligation_id: obligation_ids)
          .order(:obligation_id, :stream_revision)
          .to_a
          .group_by(&:obligation_id)
      end

      def filtered(relation, query, observed_at:)
        relation = relation.where(obligation_id: query.obligation_id) if query.obligation_id
        relation = relation.where(change_set_id: query.change_set_id) if query.change_set_id
        relation = either(relation, :candidate_id, query.candidate_id) if query.candidate_id
        relation = either(relation, :work_item_id, query.work_item_id) if query.work_item_id
        relation = either(relation, :repository_id, query.repository_id) if query.repository_id
        relation = relation.where(kind: query.kind) if query.kind
        relation = relation.where(enforcement: query.enforcement) if query.enforcement
        relation = relation.where(claimant_id: query.claimant_id) if query.claimant_id
        relation = filter_claim_state(relation, query, observed_at:)
        relation.where(status: query.status)
      end

      def filter_claim_state(relation, query, observed_at:)
        case query.claim_state
        when "unclaimed"
          relation.where(claim_id: nil)
        when "active"
          relation.where.not(claim_id: nil).where("claim_expires_at_domain > ?", observed_at)
        when "expired"
          relation.where.not(claim_id: nil).where("claim_expires_at_domain <= ?", observed_at)
        else
          relation
        end
      end

      def either(relation, field, value)
        relation.where(
          "source_#{field} = :value OR target_#{field} = :value",
          value:
        )
      end

      def build(record, observed_at:, evidence_records:)
        obligation = projected_obligation(record)
        VerificationObligationViewV1.new(
          **obligation.to_h,
          status: record.status,
          evidence: creation_evidence(record),
          claim_state: claim_state(record, observed_at:),
          claim: claim_view(record),
          progress: VerificationObligationProgressV1.new(
            required_evidence_kinds: obligation.required_evidence,
            passed_evidence_kinds: record.passed_evidence_kinds,
            missing_evidence_kinds: record.missing_evidence_kinds,
            evidence_count: record.evidence_count
          ),
          submitted_evidence: evidence_records.map { evidence_view(_1) },
          outcome: outcome_view(record)
        )
      end

      def outcome_view(record)
        return unless record.terminal_outcome

        build_outcome_view(record.status, symbolize(record.terminal_outcome), evidence: terminal_evidence(record))
      end

      def terminal_evidence(record)
        evidence(
          event: record.terminal_event,
          actor: record.terminal_actor,
          markers: record.terminal_markers,
          metadata: record.terminal_metadata,
          global_position: record.terminal_event_global_position,
          occurred_at: record.terminal_at_domain,
          persisted_at: record.terminal_created_at_store,
          causation_id: record.terminal_causation_id,
          correlation_id: record.terminal_correlation_id
        )
      end

      def creation_evidence(record)
        evidence(
          event: record.event,
          actor: record.actor,
          markers: record.markers,
          metadata: record.metadata,
          global_position: record.event_global_position,
          occurred_at: record.created_at_domain,
          persisted_at: record.created_at_store,
          causation_id: record.causation_id,
          correlation_id: record.correlation_id
        )
      end

      def claim_view(record)
        return unless record.claim

        claim = Coordinator::Write::Events::VerificationObligationClaimedV2.new(symbolize(record.claim))
        VerificationObligationClaimViewV1.new(
          **claim.to_h,
          obligation_event: creation_reference(record),
          claimed_at: record.claim_claimed_at_domain.utc.iso8601(6),
          evidence: claim_evidence(record)
        )
      end

      def evidence_view(record)
        submission = projected_submission(record)
        obligation_record = Coordinator::Read::VerificationObligation.find(record.obligation_id)
        obligation = projected_obligation(obligation_record)
        VerificationEvidenceViewV1.new(
          **submission.to_h,
          obligation_event: creation_reference(obligation_record),
          source_candidate: obligation.source_candidate,
          target_candidate: obligation.target_candidate,
          policy: obligation.policy,
          obligation_validity_input_digest: record.metadata.fetch(
            "obligation_validity_input_digest"
          ),
          assessment_input_digest: record.metadata.fetch("assessment_input_digest"),
          submitted_at: record.submitted_at_domain.utc.iso8601(6),
          evidence: evidence(
            event: record.event,
            actor: record.actor,
            markers: record.markers,
            metadata: record.metadata,
            global_position: record.event_global_position,
            occurred_at: record.submitted_at_domain,
            persisted_at: record.created_at_store,
            causation_id: record.causation_id,
            correlation_id: record.correlation_id
          )
        )
      end

      def build_outcome_view(status, payload, evidence:)
        klass = case status
        when "satisfied" then VerificationObligationSatisfiedViewV1
        when "failed" then VerificationObligationFailedViewV1
        when "waived" then VerificationObligationWaivedViewV1
        when "invalidated" then VerificationObligationInvalidatedViewV1
        end
        klass.new(**payload, evidence:)
      end

      def claim_evidence(record)
        evidence(
          event: record.claim_event,
          actor: record.claim_actor,
          markers: record.claim_markers,
          metadata: record.claim_metadata,
          global_position: record.claim_event_global_position,
          occurred_at: record.claim_claimed_at_domain,
          persisted_at: record.claim_created_at_store,
          causation_id: record.claim_causation_id,
          correlation_id: record.claim_correlation_id
        )
      end

      def claim_state(record, observed_at:)
        return "unclaimed" unless record.claim_id

        record.claim_expires_at_domain > observed_at ? "active" : "expired"
      end

      def evidence(
        event:,
        actor:,
        markers:,
        metadata:,
        global_position:,
        occurred_at:,
        persisted_at:,
        causation_id:,
        correlation_id:
      )
        VerificationObligationEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(event)),
          actor: AttributedActorV1.new(symbolize(actor)),
          markers:,
          metadata:,
          global_position:,
          occurred_at: occurred_at.utc.iso8601(6),
          persisted_at: persisted_at.utc.iso8601(6),
          causation_id:,
          correlation_id:
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
