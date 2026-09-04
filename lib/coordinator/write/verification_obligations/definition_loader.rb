# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligations
    class DefinitionLoader
      FACT_TYPES = %w[
        VerificationObligationCreated
        VerificationObligationAddedToChangeSet
        VerificationObligationSourceCandidateAssigned
        VerificationObligationTargetCandidateAssigned
      ].freeze

      def initialize(
        event_store:,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        candidate_state_loader: Candidates::StateLoader.new(event_store:),
        candidate_evidence_loader: CandidateObligations::CandidateEvidenceLoader.new(event_store:),
        matcher: CandidateObligations::Matcher.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @candidate_state_loader = candidate_state_loader
        @candidate_evidence_loader = candidate_evidence_loader
        @matcher = matcher
      end

      def call(obligation_id)
        events = @event_store.read(
          @stream_factory.verification_obligation(obligation_id),
          EventReadCriteria.new(event_types: FACT_TYPES, maximum_count: 4, direction: :asc)
        )
        return if events.empty?
        unless events.length == 4
          raise InvalidHistory, "Verification obligation definition is incomplete"
        end

        facts = events.to_h { [ _1.type, [ load_event(_1), _1 ] ] }
        created, created_event = facts.fetch("VerificationObligationCreated")
        membership, = facts.fetch("VerificationObligationAddedToChangeSet")
        source_assignment, = facts.fetch("VerificationObligationSourceCandidateAssigned")
        target_assignment, = facts.fetch("VerificationObligationTargetCandidateAssigned")
        identifiers = [
          created.obligation_id,
          membership.obligation_id,
          source_assignment.obligation_id,
          target_assignment.obligation_id
        ]
        unless identifiers.all? { _1 == obligation_id }
          raise InvalidHistory, "Verification obligation facts disagree on obligation_id"
        end

        source = candidate_evidence(source_assignment.candidate_id)
        target = candidate_evidence(target_assignment.candidate_id)
        reasons = @matcher.call(source:, target:)
        unless created.reasons == reasons.map(&:kind)
          raise InvalidHistory, "Verification obligation reasons disagree with Candidate evidence"
        end

        metadata = created_event.metadata
        definition = DefinitionV2.new(
          obligation_id:,
          kind: created.kind,
          change_set_id: membership.change_set_id,
          source_candidate: source.subject,
          target_candidate: target.subject,
          reasons:,
          required_evidence: created.required_evidence,
          enforcement: created.enforcement,
          policy: CandidateObligations::ImpactPolicyEvidenceV1.new(
            deep_symbolize(metadata.fetch("policy"))
          ),
          validity_input_digest: metadata.fetch("validity_input_digest"),
          rule_version: metadata.fetch("rule_version"),
          created_at: created_event.created_at.utc.iso8601(6)
        )
        LoadedDefinitionV2.new(
          definition:,
          event: created_event,
          reference: event_reference(created_event)
        )
      end

      private

      def candidate_evidence(candidate_id)
        state = @candidate_state_loader.call(candidate_id)
        unless state&.surface_assignment_event
          raise InvalidHistory, "Verification obligation Candidate has no impact surface"
        end

        @candidate_evidence_loader.call(state.surface_assignment_event)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def deep_symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, deep_symbolize(nested) ] }
        when Array then value.map { deep_symbolize(_1) }
        else value
        end
      end
    end
  end
end
