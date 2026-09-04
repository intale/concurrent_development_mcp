# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class CandidateEvidenceLoader
      def initialize(
        event_store:,
        exact_loader: ExactEventLoader.new(event_store:),
        candidate_loader: Candidates::StateLoader.new(event_store:),
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new,
        evidence_contract: Contracts::CandidateObligationEvidence.new
      )
        @event_store = event_store
        @exact_loader = exact_loader
        @candidate_loader = candidate_loader
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @evidence_contract = evidence_contract
      end

      def call(registration_reference)
        persisted_registration = @exact_loader.call(registration_reference)
        registration = payload!(persisted_registration, Events::CandidateImpactSurfaceAssignedV1)
        candidate = @candidate_loader.call(registration.candidate_id)
        unless candidate && candidate.surface_assignment_event == registration_reference
          raise InvalidHistory.new(
            reason: "candidate_surface_assignment_mismatch",
            evidence: { reference: registration_reference.to_h }
          )
        end

        surface_event = load_surface_event(registration.surface_id)
        surface = load_surface(surface_event)
        evidence = CandidateEvidenceV2.new(
          registration:,
          registration_event: registration_reference,
          registration_global_position: persisted_registration.event.global_position,
          candidate:,
          surface:,
          surface_event: event_reference(surface_event),
          surface_digest: surface_event.metadata.fetch("surface_digest"),
          subject: build_subject(registration_reference, candidate, surface_event)
        )
        validation = @evidence_contract.call(evidence:)
        return evidence if validation.success?

        raise InvalidHistory.new(
          reason: "candidate_evidence_mismatch",
          evidence: validation.errors.to_h
        )
      end

      private

      def load_surface_event(surface_id)
        event = @event_store.read(
          @stream_factory.candidate_impact_surface(surface_id),
          EventReadCriteria.new(
            event_types: [ "CandidateImpactSurfaceDerived" ],
            maximum_count: 1,
            direction: :asc
          )
        ).first
        return event if event

        raise InvalidHistory.new(
          reason: "candidate_impact_surface_not_found",
          evidence: { surface_id: }
        )
      end

      def load_surface(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def payload!(persisted, *expected_classes)
        return persisted.payload if expected_classes.any? { persisted.payload.is_a?(_1) }

        raise InvalidHistory.new(
          reason: "referenced_event_type_invalid",
          evidence: {
            reference: persisted.reference.to_h,
            expected_classes: expected_classes.map(&:name),
            actual_class: persisted.payload.class.name
          }
        )
      end

      def build_subject(registration_reference, candidate, surface_event)
        CandidateSubjectV1.new(
          candidate_id: candidate.candidate_id,
          change_set_id: candidate.change_set_id,
          work_item_id: candidate.work_item_id,
          attempt_id: candidate.attempt_id,
          repository_id: candidate.repository_id,
          target_branch: candidate.target_branch,
          object_format: candidate.object_format,
          base_commit_oid: candidate.base_commit_oid,
          head_commit_oid: candidate.head_commit_oid,
          manifest_digest: candidate.manifest_digest,
          build_context_digest: candidate.build_context_digest,
          surface_digest: surface_event.metadata.fetch("surface_digest"),
          candidate_event: candidate.submission_event,
          manifest_event: candidate.manifest_event,
          build_context_event: candidate.build_context_event,
          surface_event: event_reference(surface_event),
          registration_event: registration_reference
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
    end
  end
end
