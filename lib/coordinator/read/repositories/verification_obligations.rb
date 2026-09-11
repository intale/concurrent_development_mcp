# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class VerificationObligations
      include EventTimestamped

      def initialize(
        evidence_contract: Contracts::VerificationEvidenceProjection.new,
        outcome_contract: Contracts::VerificationOutcomeProjection.new,
        lifecycle_contract: Contracts::VerificationLifecycleProjection.new
      )
        @evidence_contract = evidence_contract
        @outcome_contract = outcome_contract
        @lifecycle_contract = lifecycle_contract
      end

      def store_creation(event:, obligation:)
        source = obligation.source_candidate
        target = obligation.target_candidate
        create_from_event(Coordinator::Read::VerificationObligation, event:, attributes: {
          obligation_id: obligation.obligation_id,
          kind: obligation.kind,
          status: obligation.status,
          change_set_id: obligation.change_set_id,
          source_candidate_id: source.candidate_id,
          target_candidate_id: target.candidate_id,
          source_work_item_id: source.work_item_id,
          target_work_item_id: target.work_item_id,
          source_repository_id: source.repository_id,
          target_repository_id: target.repository_id,
          enforcement: obligation.enforcement,
          obligation: obligation.to_h,
          event: event_reference(event).to_h,
          actor: actor(event).to_h,
          markers: event.markers,
          metadata: event.metadata,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          event_global_position: event.global_position,
          created_at_domain: obligation.created_at,
          created_at_store: event.created_at,
          evidence_count: 0,
          passed_evidence_kinds: [],
          missing_evidence_kinds: obligation.required_evidence
        })
      end

      def store_definition_v2(event:, loaded:)
        definition = loaded.definition
        record = Coordinator::Read::VerificationObligation.find_or_initialize_by(
          obligation_id: definition.obligation_id
        )
        attributes = if record.new_record?
          source = definition.source_candidate
          target = definition.target_candidate
          created_event = loaded.event
          {
            obligation_id: definition.obligation_id,
            kind: definition.kind,
            status: "open",
            change_set_id: definition.change_set_id,
            source_candidate_id: source.candidate_id,
            target_candidate_id: target.candidate_id,
            source_work_item_id: source.work_item_id,
            target_work_item_id: target.work_item_id,
            source_repository_id: source.repository_id,
            target_repository_id: target.repository_id,
            enforcement: definition.enforcement,
            obligation: definition.to_h,
            event: loaded.reference.to_h,
            actor: actor(created_event).to_h,
            markers: created_event.markers,
            metadata: created_event.metadata,
            causation_id: created_event.causation_id,
            correlation_id: created_event.correlation_id,
            event_global_position: created_event.global_position,
            created_at_domain: created_event.created_at,
            created_at_store: created_event.created_at,
            evidence_count: 0,
            passed_evidence_kinds: [],
            missing_evidence_kinds: definition.required_evidence
          }
        else
          {}
        end
        save_from_event(record, event:, attributes:)
      end

      def store_claim(event:, claim:)
        record = Coordinator::Read::VerificationObligation.find_by(
          obligation_id: claim.obligation_id
        )
        unless record
          raise InvalidProjectionSource,
                "VerificationObligationClaimed cannot precede VerificationObligationCreated"
        end
        return record if record.claim_stream_revision && record.claim_stream_revision >= event.stream_revision

        attributes = {
          claim: claim.to_h,
          claim_id: claim.claim_id,
          claimant_id: claim.claimant_id,
          claim_fencing_token: claim.fencing_token,
          claim_claimed_at_domain: claim.claimed_at,
          claim_expires_at_domain: claim.expires_at,
          claim_event: event_reference(event).to_h,
          claim_actor: actor(event).to_h,
          claim_markers: event.markers,
          claim_metadata: event.metadata,
          claim_causation_id: event.causation_id,
          claim_correlation_id: event.correlation_id,
          claim_event_global_position: event.global_position,
          claim_stream_revision: event.stream_revision,
          claim_created_at_store: event.created_at
        }
        save_from_event(record, event:, attributes:)
        record
      end

      def store_claim_v2(event:, claim:)
        record = find_obligation!(claim.obligation_id, event.type)
        return record if record.claim_stream_revision && record.claim_stream_revision >= event.stream_revision

        save_from_event(record, event:, attributes: {
          claim: claim.to_h,
          claim_id: claim.claim_id,
          claimant_id: claim.claimant_id,
          claim_fencing_token: claim.fencing_token,
          claim_claimed_at_domain: event.created_at,
          claim_expires_at_domain: claim.expires_at,
          claim_event: event_reference(event).to_h,
          claim_actor: actor(event).to_h,
          claim_markers: event.markers,
          claim_metadata: event.metadata,
          claim_causation_id: event.causation_id,
          claim_correlation_id: event.correlation_id,
          claim_event_global_position: event.global_position,
          claim_stream_revision: event.stream_revision,
          claim_created_at_store: event.created_at
        })
      end

      def store_evidence(event:, submission:)
        record = find_obligation!(
          submission.obligation_id,
          "VerificationEvidenceSubmitted"
        )
        claim = projected_claim!(record)
        reference = event_reference(event)
        validation = @evidence_contract.call(
          obligation: projected_obligation(record),
          obligation_event: creation_reference(record),
          claim:,
          claim_event: claim_reference(record),
          submission:,
          submission_event: reference,
          actor_id: event.metadata.fetch("actor_id"),
          current_status: record.status,
          evidence_count: record.evidence_count
        )
        raise InvalidProjectionSource, validation.errors.to_h.inspect if validation.failure?

        assessment = submission.assessment
        create_from_event(Coordinator::Read::VerificationObligationEvidenceItem, event:, attributes: {
          evidence_id: submission.evidence_id,
          obligation_id: submission.obligation_id,
          evidence_kind: submission.evidence_kind,
          conclusion: assessment.conclusion,
          assessment_input_digest: submission.assessment_input_digest,
          result_digest: assessment.result_digest,
          submission: submission.to_h,
          event_id: event.id,
          event: reference.to_h,
          actor: actor(event).to_h,
          markers: event.markers,
          metadata: event.metadata,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          event_global_position: event.global_position,
          stream_revision: event.stream_revision,
          produced_at_domain: assessment.produced_at,
          submitted_at_domain: submission.submitted_at,
          created_at_store: event.created_at
        })
        update_progress(record, event:)
      end

      def store_evidence_v2(event:, submission:)
        record = find_obligation!(submission.obligation_id, event.type)
        assessment = submission.assessment
        create_from_event(Coordinator::Read::VerificationObligationEvidenceItem, event:, attributes: {
          evidence_id: submission.evidence_id,
          obligation_id: submission.obligation_id,
          evidence_kind: submission.evidence_kind,
          conclusion: assessment.conclusion,
          assessment_input_digest: event.metadata.fetch("assessment_input_digest"),
          result_digest: assessment.result_digest,
          submission: submission.to_h,
          event_id: event.id,
          event: event_reference(event).to_h,
          actor: actor(event).to_h,
          markers: event.markers,
          metadata: event.metadata,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          event_global_position: event.global_position,
          stream_revision: event.stream_revision,
          produced_at_domain: assessment.produced_at,
          submitted_at_domain: event.created_at,
          created_at_store: event.created_at
        })
        update_progress(record, event:)
      end

      def touch_from_event(event:, obligation_id:)
        record = find_obligation!(obligation_id, event.type)
        save_from_event(record, event:)
      end

      def store_outcome(event:, outcome:)
        record = find_obligation!(outcome.obligation_id, event.type)
        observations = projected_evidence(record.obligation_id)
        validation = @outcome_contract.call(
          obligation: projected_obligation(record),
          obligation_event: creation_reference(record),
          evidence: observations,
          outcome:,
          outcome_event: event_reference(event),
          current_status: record.status
        )
        raise InvalidProjectionSource, validation.errors.to_h.inspect if validation.failure?

        save_from_event(record, event:, attributes: {
          status: terminal_status(outcome),
          terminal_outcome: outcome.to_h,
          terminal_event: event_reference(event).to_h,
          terminal_actor: actor(event).to_h,
          terminal_markers: event.markers,
          terminal_metadata: event.metadata,
          terminal_causation_id: event.causation_id,
          terminal_correlation_id: event.correlation_id,
          terminal_event_global_position: event.global_position,
          terminal_stream_revision: event.stream_revision,
          terminal_at_domain: terminal_at(outcome),
          terminal_created_at_store: event.created_at
        })
        record
      end

      def store_outcome_v2(event:, outcome:, state:)
        record = find_obligation!(outcome.obligation_id, event.type)
        selected = state.selected_evidence_ids.map do |evidence_id|
          state.observation(evidence_id)&.decision_reference
        end
        if selected.any?(&:nil?)
          raise InvalidProjectionSource, "Verification obligation outcome references missing evidence"
        end

        payload = if outcome.is_a?(Coordinator::Write::Events::VerificationObligationSatisfiedV2)
          {
            obligation_id: outcome.obligation_id,
            obligation_event: creation_reference(record).to_h,
            policy: projected_obligation(record).policy.to_h,
            selected_evidence: selected.map(&:to_h),
            outcome_digest: event.metadata.fetch("outcome_digest"),
            satisfied_at: event.created_at.utc.iso8601(6)
          }
        else
          triggering = selected.sole
          {
            obligation_id: outcome.obligation_id,
            obligation_event: creation_reference(record).to_h,
            policy: projected_obligation(record).policy.to_h,
            triggering_evidence: triggering.to_h,
            outcome_digest: event.metadata.fetch("outcome_digest"),
            failed_at: event.created_at.utc.iso8601(6)
          }
        end
        save_from_event(
          record,
          event:,
          attributes: terminal_attributes_v2(event, status: state.terminal_status, payload:)
        )
      end

      def store_lifecycle(event:, transition:)
        record = find_obligation!(transition.obligation_id, event.type)
        validation = @lifecycle_contract.call(
          obligation: projected_obligation(record),
          obligation_event: creation_reference(record),
          transition:,
          transition_event: event_reference(event),
          current_status: record.status,
          current_terminal_event: record.terminal_event && terminal_reference(record)
        )
        raise InvalidProjectionSource, validation.errors.to_h.inspect if validation.failure?

        save_from_event(record, event:, attributes: terminal_attributes(event, transition))
        record
      end

      def store_lifecycle_v2(event:, transition:)
        record = find_obligation!(transition.obligation_id, event.type)
        previous_status = record.status
        previous_terminal_event = record.terminal_event && terminal_reference(record)
        definition = projected_obligation(record)
        status = event.type.delete_prefix("VerificationObligation").downcase
        payload = if transition.is_a?(Coordinator::Write::Events::VerificationObligationWaivedV2)
          {
            obligation_id: transition.obligation_id,
            obligation_event: creation_reference(record).to_h,
            policy: definition.policy.to_h,
            previous_status:,
            previous_terminal_event: previous_terminal_event&.to_h,
            reason: transition.reason.to_h,
            waiver_input_digest: event.metadata.fetch("waiver_input_digest"),
            waived_at: event.created_at.utc.iso8601(6)
          }
        else
          {
            obligation_id: transition.obligation_id,
            obligation_event: creation_reference(record).to_h,
            invalidated_policy: definition.policy.to_h,
            superseding_partition_event: transition.superseding_partition_event.to_h,
            previous_status:,
            previous_terminal_event: previous_terminal_event&.to_h,
            reason: transition.reason,
            invalidation_digest: event.metadata.fetch("invalidation_digest"),
            rule_version: event.metadata.fetch("rule_version"),
            invalidated_at: event.created_at.utc.iso8601(6)
          }
        end
        save_from_event(record, event:, attributes: terminal_attributes_v2(event, status:, payload:))
      end

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

      def find_obligation!(obligation_id, event_type)
        record = Coordinator::Read::VerificationObligation.find_by(obligation_id:)
        return record if record

        raise InvalidProjectionSource,
              "#{event_type} cannot precede VerificationObligationCreated"
      end

      def projected_obligation(record)
        attributes = symbolize(record.obligation)
        if record.metadata.fetch("schema_version") == 2
          Coordinator::Write::VerificationObligations::DefinitionV2.new(attributes)
        else
          Coordinator::Write::Events::VerificationObligationCreatedV1.new(attributes)
        end
      end

      def projected_claim!(record)
        return Coordinator::Write::Events::VerificationObligationClaimedV1.new(symbolize(record.claim)) if record.claim

        raise InvalidProjectionSource,
              "VerificationEvidenceSubmitted cannot precede VerificationObligationClaimed"
      end

      def creation_reference(record)
        Coordinator::Write::EventReference.new(symbolize(record.event))
      end

      def claim_reference(record)
        Coordinator::Write::EventReference.new(symbolize(record.claim_event))
      end

      def update_progress(record, event:)
        relation = Coordinator::Read::VerificationObligationEvidenceItem.where(
          obligation_id: record.obligation_id
        )
        required = projected_obligation(record).required_evidence
        passed_set = relation.where(conclusion: "passed").distinct.pluck(:evidence_kind)
        passed = required.select { passed_set.include?(_1) }
        save_from_event(record, event:, attributes: {
          evidence_count: relation.count,
          passed_evidence_kinds: passed,
          missing_evidence_kinds: required - passed
        })
        record
      end

      def projected_evidence(obligation_id)
        Coordinator::Read::VerificationObligationEvidenceItem
          .where(obligation_id:)
          .order(:stream_revision)
          .map do |record|
            VerificationEvidenceProjectionObservationV1.new(
              submission: projected_submission(record),
              event: Coordinator::Write::EventReference.new(symbolize(record.event))
            )
          end
      end

      def projected_submission(record)
        attributes = symbolize(record.submission)
        if record.metadata.fetch("schema_version") == 2
          Coordinator::Write::Events::VerificationEvidenceSubmittedV2.new(attributes)
        else
          Coordinator::Write::Events::VerificationEvidenceSubmittedV1.new(attributes)
        end
      end

      def terminal_status(outcome)
        case outcome
        when Coordinator::Write::Events::VerificationObligationSatisfiedV1,
             Coordinator::Write::Events::VerificationObligationSatisfiedV2 then "satisfied"
        when Coordinator::Write::Events::VerificationObligationFailedV1,
             Coordinator::Write::Events::VerificationObligationFailedV2 then "failed"
        when Coordinator::Write::Events::VerificationObligationWaivedV1,
             Coordinator::Write::Events::VerificationObligationWaivedV2 then "waived"
        when Coordinator::Write::Events::VerificationObligationInvalidatedV1,
             Coordinator::Write::Events::VerificationObligationInvalidatedV2 then "invalidated"
        end
      end

      def terminal_at(outcome)
        case outcome
        when Coordinator::Write::Events::VerificationObligationSatisfiedV1 then outcome.satisfied_at
        when Coordinator::Write::Events::VerificationObligationFailedV1 then outcome.failed_at
        when Coordinator::Write::Events::VerificationObligationWaivedV1 then outcome.waived_at
        when Coordinator::Write::Events::VerificationObligationInvalidatedV1 then outcome.invalidated_at
        end
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

      def evidence_view(record)
        submission = projected_submission(record)
        return evidence_view_v2(record, submission) if submission.is_a?(
          Coordinator::Write::Events::VerificationEvidenceSubmittedV2
        )

        VerificationEvidenceViewV1.new(
          **submission.to_h,
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

      def outcome_view(record)
        return unless record.terminal_outcome

        payload = symbolize(record.terminal_outcome)
        evidence = terminal_evidence(record)
        if record.terminal_metadata.fetch("schema_version") == 2
          return outcome_view_v2(record.status, payload, evidence:)
        end

        case record.status
        when "satisfied"
          outcome = Coordinator::Write::Events::VerificationObligationSatisfiedV1.new(payload)
          VerificationObligationSatisfiedViewV1.new(**outcome.to_h, evidence:)
        when "failed"
          outcome = Coordinator::Write::Events::VerificationObligationFailedV1.new(payload)
          VerificationObligationFailedViewV1.new(**outcome.to_h, evidence:)
        when "waived"
          outcome = Coordinator::Write::Events::VerificationObligationWaivedV1.new(payload)
          VerificationObligationWaivedViewV1.new(**outcome.to_h, evidence:)
        when "invalidated"
          outcome = Coordinator::Write::Events::VerificationObligationInvalidatedV1.new(payload)
          VerificationObligationInvalidatedViewV1.new(**outcome.to_h, evidence:)
        end
      end

      def terminal_attributes(event, transition)
        {
          status: terminal_status(transition),
          terminal_outcome: transition.to_h,
          terminal_event: event_reference(event).to_h,
          terminal_actor: actor(event).to_h,
          terminal_markers: event.markers,
          terminal_metadata: event.metadata,
          terminal_causation_id: event.causation_id,
          terminal_correlation_id: event.correlation_id,
          terminal_event_global_position: event.global_position,
          terminal_stream_revision: event.stream_revision,
          terminal_at_domain: terminal_at(transition),
          terminal_created_at_store: event.created_at
        }
      end

      def terminal_attributes_v2(event, status:, payload:)
        {
          status:,
          terminal_outcome: payload,
          terminal_event: event_reference(event).to_h,
          terminal_actor: actor(event).to_h,
          terminal_markers: event.markers,
          terminal_metadata: event.metadata,
          terminal_causation_id: event.causation_id,
          terminal_correlation_id: event.correlation_id,
          terminal_event_global_position: event.global_position,
          terminal_stream_revision: event.stream_revision,
          terminal_at_domain: event.created_at,
          terminal_created_at_store: event.created_at
        }
      end

      def terminal_reference(record)
        Coordinator::Write::EventReference.new(symbolize(record.terminal_event))
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

        if record.claim_metadata.fetch("schema_version") == 2
          claim = Coordinator::Write::Events::VerificationObligationClaimedV2.new(
            symbolize(record.claim)
          )
          return VerificationObligationClaimViewV1.new(
            **claim.to_h,
            obligation_event: creation_reference(record),
            claimed_at: record.claim_claimed_at_domain.utc.iso8601(6),
            evidence: claim_evidence(record)
          )
        end

        claim = Coordinator::Write::Events::VerificationObligationClaimedV1.new(symbolize(record.claim))
        VerificationObligationClaimViewV1.new(
          **claim.to_h,
          evidence: claim_evidence(record)
        )
      end

      def evidence_view_v2(record, submission)
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

      def outcome_view_v2(status, payload, evidence:)
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
