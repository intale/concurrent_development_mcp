# frozen_string_literal: true

module Coordinator::Read::Projections
  class MergeSnapshots
    def initialize(snapshots:, authorizations:, documents: {})
      @snapshots, @authorizations, @documents = snapshots, authorizations, documents
    end

    def apply(event, registration: nil)
      data = Coordinator::Read::CommandResults::Source.document(event.data)
      id = data.fetch(:merge_snapshot_id)
      @documents[id] ||= {}
      case event.type
      when "MergeSnapshotRegistered" then register(event, registration)
      when "MergeSnapshotVerificationSubmitted" then submission(event, data)
      when "MergeSnapshotVerificationSelected"
        assign(id, verified_decision: value(id, :verified_decision, {}).merge(
          verification_id: data.fetch(:verification_id), selected_event: Source.reference(event)))
      when "MergeSnapshotVerified" then verified(event, data)
      when "MergeAuthorizationGranted", "MergeAuthorizationDenied" then authorization(event, data)
      when "MergeObserved" then observation(event, data)
      when "MergeObservationAuthorizationLinked"
        assign(id, observation: value(id, :observation, {}).merge(authorization_event: data.fetch(:authorization_event)))
      end
      @snapshots.touch({ merge_snapshot_id: id }, time: event.created_at)
      nil
    end

    private

    def register(event, registration)
      attributes = registration.except(:produced_at).merge(produced_at_domain: registration.fetch(:produced_at),
        snapshot_digest: event.metadata.fetch("snapshot_digest"), policy_version: event.metadata.fetch("policy_version"),
        evidence_status: "attributed_unverified").merge(Source.evidence(event, prefix: :registered))
      @snapshots.insert(attributes.merge(verification_status: "unverified", verification_submissions: [], verified_decision: nil,
        observation: nil, created_at: event.created_at, updated_at: event.created_at))
      @snapshots.assign(attributes)
    end

    def submission(event, data)
      id = data.fetch(:merge_snapshot_id)
      entry = data.slice(:verification_id, :assessment).merge(policy_version: event.metadata.fetch("policy_version"),
        verification_input_digest: event.metadata.fetch("verification_input_digest"), submitted_at: timestamp(event), source: evidence(event))
      entries = value(id, :verification_submissions, []).dup
      index = entries.index { _1.fetch(:verification_id) == data.fetch(:verification_id) }
      index ? entries[index] = entry : entries << entry
      conclusion = data.fetch(:assessment).fetch(:conclusion)
      assign(id, verification_submissions: entries, verification_status: conclusion == "passed" ? "unverified" : conclusion,
        verification_policy_version: event.metadata.fetch("policy_version"))
    end

    def verified(event, data)
      id = data.fetch(:merge_snapshot_id)
      selection = value(id, :verified_decision, {})
      selected_id = selection.fetch(:verification_id)
      submitted = value(id, :verification_submissions, []).find { _1.fetch(:verification_id) == selected_id }
      selected = submitted.fetch(:assessment).slice(:evidence_kind, :conclusion, :result_digest).merge(
        verification_id: selected_id, verification_input_digest: submitted.fetch(:verification_input_digest), event: submitted.fetch(:source).fetch(:event))
      outcome = selection.merge(policy_version: event.metadata.fetch("policy_version"), selected_verification: selected,
        verification_digest: event.metadata.fetch("verification_digest"), verified_at: timestamp(event), source: evidence(event))
      assign(id, verification_status: "verified", verification_policy_version: event.metadata.fetch("policy_version"), verified_decision: outcome)
    end

    def authorization(event, data)
      attributes = data.merge(outcome: event.type == "MergeAuthorizationGranted" ? "granted" : "denied",
        policy_version: event.metadata.fetch("policy_version"), expected_impact_policy: event.metadata["expected_impact_policy"],
        input_digest: event.metadata.fetch("input_digest"), decision_digest: event.metadata.fetch("decision_digest"), decided_at_domain: event.created_at,
        source_event: Source.reference(event), source_actor: Source.actor(event), source_markers: event.markers,
        source_metadata: event.metadata, source_causation_id: event.causation_id, source_correlation_id: event.correlation_id,
        source_global_position: event.global_position, source_persisted_at: event.created_at)
      @authorizations.insert(attributes.merge(created_at: event.created_at, updated_at: event.created_at))
      @authorizations.assign(attributes)
      @authorizations.touch(attributes.slice(:authorization_id), time: event.created_at)
    end

    def observation(event, data)
      id = data.fetch(:merge_snapshot_id)
      existing = value(id, :observation, {})
      initial = existing.dig(:source, :event, :event_id) == event.id ? existing : { authorization_event: nil }
      observed = initial.merge(data.except(:merge_snapshot_id)).merge(
        authorization_decision_digest: event.metadata.fetch("authorization_decision_digest"),
        observation_digest: event.metadata.fetch("observation_digest"), policy_version: event.metadata.fetch("policy_version"),
        evidence_status: "attributed_unverified", recorded_at: timestamp(event), source: evidence(event))
      assign(id, observation: observed)
    end

    def assign(id, **attributes)
      @documents.fetch(id).merge!(attributes)
      @snapshots.assign({ merge_snapshot_id: id }.merge(attributes))
    end

    def value(id, column, default)
      @documents.fetch(id).fetch(column, nil) || default
    end

    def timestamp(event)
      event.created_at.utc.iso8601(6)
    end

    def evidence(event)
      { event: Source.reference(event), actor: Source.actor(event), markers: event.markers, metadata: event.metadata,
        global_position: event.global_position, occurred_at: timestamp(event), persisted_at: timestamp(event),
        causation_id: event.causation_id, correlation_id: event.correlation_id }
    end
  end
end
