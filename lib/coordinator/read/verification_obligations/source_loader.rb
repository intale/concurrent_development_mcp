# frozen_string_literal: true

module Coordinator::Read::VerificationObligations
  # Bounded immutable evidence for presentation, not Write-side state/validation.
  class SourceLoader
    DEFINITION_TYPES = %w[VerificationObligationCreated VerificationObligationAddedToChangeSet
      VerificationObligationSourceCandidateAssigned VerificationObligationTargetCandidateAssigned].freeze
    CANDIDATE_TYPES = %w[CandidateAssignedToAttempt CandidateAssignedToRepository CandidateTargetBranchSelected
      CandidateCommitRangeDeclared CandidateChangeManifestCaptured CandidateBuildContextCaptured CandidateSubmitted
      CandidateImpactSurfaceAssigned].freeze
    TERMINAL_TYPES = %w[VerificationObligationSatisfied VerificationObligationFailed
      VerificationObligationWaived VerificationObligationInvalidated].freeze
    OUTCOME_TYPES = [ "VerificationEvidenceSubmitted", "VerificationObligationEvidenceSelected", *TERMINAL_TYPES ].freeze

    def initialize(event_store:, stream_factory: Coordinator::Write::StreamFactory.new)
      @event_store, @stream_factory = event_store, stream_factory
    end

    def definition(obligation_id)
      events = @event_store.read(@stream_factory.verification_obligation(obligation_id), Coordinator::Write::EventReadCriteria.new(
        event_types: DEFINITION_TYPES, maximum_count: DEFINITION_TYPES.length, direction: :asc))
      facts = events.to_h { [ _1.type, _1 ] }
      created = facts.fetch("VerificationObligationCreated")
      data = document(created.data)
      source = candidate(facts.fetch("VerificationObligationSourceCandidateAssigned").data.fetch("candidate_id"))
      target = candidate(facts.fetch("VerificationObligationTargetCandidateAssigned").data.fetch("candidate_id"))
      definition = data.merge(change_set_id: facts.fetch("VerificationObligationAddedToChangeSet").data.fetch("change_set_id"),
        source_candidate: source.fetch(:subject), target_candidate: target.fetch(:subject),
        reasons: data.fetch(:reasons).map { reason(_1, source:, target:) },
        policy: document(created.metadata.fetch("policy")), validity_input_digest: created.metadata.fetch("validity_input_digest"),
        rule_version: created.metadata.fetch("rule_version"), created_at: timestamp(created))
      DefinitionSource.new(document: definition, event: created)
    end

    def outcome(event, definition:)
      stream = @stream_factory.verification_obligation(event.data.fetch("obligation_id"))
      events = @event_store.read(stream, Coordinator::Write::EventReadCriteria.new(event_types: OUTCOME_TYPES,
        maximum_count: 2 * Coordinator::Write::Types::VERIFICATION_EVIDENCE_MAXIMUM_COUNT + TERMINAL_TYPES.length,
        direction: :asc, to_revision: event.stream_revision))
      data = document(event.data)
      policy = definition.document.fetch(:policy)
      common = { obligation_id: data.fetch(:obligation_id), obligation_event: reference(definition.event) }
      case event.type
      when "VerificationObligationSatisfied", "VerificationObligationFailed"
        evidence = events.select { _1.type == "VerificationEvidenceSubmitted" }.to_h { [ _1.data.fetch("evidence_id"), _1 ] }
        selected = events.select { _1.type == "VerificationObligationEvidenceSelected" }.map do |selection|
          decision_reference(evidence.fetch(selection.data.fetch("evidence_id")))
        end
        common.merge(policy:, outcome_digest: event.metadata.fetch("outcome_digest")).merge(
          event.type == "VerificationObligationSatisfied" ?
            { selected_evidence: selected, satisfied_at: timestamp(event) } :
            { triggering_evidence: selected.first, failed_at: timestamp(event) })
      else
        previous = events.reverse.find { TERMINAL_TYPES.include?(_1.type) && _1.stream_revision < event.stream_revision }
        common.merge(previous_status: previous ? status(previous) : "open", previous_terminal_event: previous && reference(previous)).merge(
          event.type == "VerificationObligationWaived" ?
            { policy:, reason: data.fetch(:reason), waiver_input_digest: event.metadata.fetch("waiver_input_digest"), waived_at: timestamp(event) } :
            { invalidated_policy: policy, superseding_partition_event: data.fetch(:superseding_partition_event), reason: data.fetch(:reason),
              invalidation_digest: event.metadata.fetch("invalidation_digest"), rule_version: event.metadata.fetch("rule_version"), invalidated_at: timestamp(event) })
      end
    end

    private

    def candidate(id)
      events = @event_store.read(@stream_factory.candidate(id), Coordinator::Write::EventReadCriteria.new(
        event_types: CANDIDATE_TYPES, maximum_count: CANDIDATE_TYPES.length, direction: :asc))
      facts = events.to_h { [ _1.type, _1 ] }
      assignment = facts.fetch("CandidateImpactSurfaceAssigned")
      surface = @event_store.read(@stream_factory.candidate_impact_surface(assignment.data.fetch("surface_id")),
        Coordinator::Write::EventReadCriteria.new(event_types: [ "CandidateImpactSurfaceDerived" ], maximum_count: 1, direction: :asc)).first
      manifest, context = facts.fetch("CandidateChangeManifestCaptured"), facts["CandidateBuildContextCaptured"]
      subject = { candidate_id: id,
        **document(facts.fetch("CandidateAssignedToAttempt").data).slice(:change_set_id, :work_item_id, :attempt_id),
        repository_id: facts.fetch("CandidateAssignedToRepository").data.fetch("repository_id"),
        target_branch: facts.fetch("CandidateTargetBranchSelected").data.fetch("target_branch"),
        **document(facts.fetch("CandidateCommitRangeDeclared").data).slice(:object_format, :base_commit_oid, :head_commit_oid),
        manifest_digest: manifest.metadata.fetch("manifest_digest"), build_context_digest: context&.metadata&.fetch("build_context_digest"),
        surface_digest: surface.metadata.fetch("surface_digest"), candidate_event: reference(facts.fetch("CandidateSubmitted")),
        manifest_event: reference(manifest), build_context_event: context && reference(context), surface_event: reference(surface), registration_event: reference(assignment) }
      { subject:, manifest: document(manifest.data), build_context: context && document(context.data), surface: document(surface.data) }
    end

    def reason(kind, source:, target:)
      case kind
      when "changed_resource_overlap", "observed_input_changed"
        target_paths = kind == "changed_resource_overlap" ? changed_paths(target) : (target[:build_context]&.fetch(:inputs)&.map { _1.fetch(:path) } || [])
        matches = changed_paths(source).intersection(target_paths).uniq.sort_by(&:b)
        { kind:, matches:, source_evidence: source.fetch(:subject).fetch(:manifest_event),
          target_evidence: target.fetch(:subject).fetch(kind == "changed_resource_overlap" ? :manifest_event : :build_context_event) }
      when "semantic_key_match"
        source_keys = impact_keys(source.fetch(:surface), %i[produces may_affect])
        target_keys = impact_keys(target.fetch(:surface), %i[consumes assumes])
        { kind:, matches: source_keys.intersection(target_keys).uniq.sort_by(&:b),
          source_evidence: source.fetch(:subject).fetch(:surface_event), target_evidence: target.fetch(:subject).fetch(:surface_event) }
      end
    end

    def changed_paths(candidate)
      candidate.fetch(:manifest).fetch(:files).flat_map do |file|
        case file.fetch(:status)
        when "added", "copied" then [ file.fetch(:new_path) ]
        when "renamed" then file.values_at(:old_path, :new_path)
        else [ file.fetch(:old_path) ]
        end
      end.compact.uniq
    end

    def impact_keys(surface, directions)
      directions.flat_map { surface.fetch(_1).map { |entry| entry.fetch(:impact_key) } }
    end

    def decision_reference(event)
      data = document(event.data)
      data.slice(:evidence_kind, :evidence_id).merge(data.fetch(:assessment).slice(:conclusion, :result_digest),
        assessment_input_digest: event.metadata.fetch("assessment_input_digest"), event: reference(event))
    end

    def document(value)
      Coordinator::Read::CommandResults::Source.document(value)
    end

    def reference(event)
      Coordinator::Read::Projections::Source.reference(event)
    end

    def timestamp(event)
      event.created_at.utc.iso8601(6)
    end

    def status(event)
      event.type.delete_prefix("VerificationObligation").downcase
    end
  end
end
