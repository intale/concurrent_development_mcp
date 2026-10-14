# frozen_string_literal: true

module Coordinator::Read::Projections
  class ReleaseSets
    def initialize(patches:, documents: {})
      @patches, @documents = patches, documents
    end

    def apply(event, preparation: nil)
      id = event.data.fetch("release_set_id")
      @documents[id] ||= {}
      data = Coordinator::Read::CommandResults::Source.document(event.data)
      case event.type
      when "ReleaseSetPrepared" then prepare(event, preparation)
      when "RepositoryIntegrationRecorded" then integration(event, data)
      when "RepositoryIntegrationMergeLinked" then merge_link(event, data)
      when "ReleaseSetVerificationRequested" then assign(id, status: "verifying")
      when "ReleaseSetVerificationRecorded" then verification(event, data)
      when "ReleaseSetIntegrationLinked" then verification_link(event, data)
      when "ReleaseSetActivated" then activation(event, data)
      when "ReleaseSetCompensationRequested" then compensation_request(event, data)
      when "ReleaseSetSuccessfulIntegrationLinked" then compensation_link(event, data)
      when "RepositoryCompensationRecorded" then repository_compensation(event, data)
      when "ReleaseSetOutcomeRecorded" then outcome(event, data)
      when "ReleaseSetCompleted"
        assign(id, status: "completed", completion: value(id, :completion, {}).merge(
          completed_at: timestamp(event), source: evidence(event)))
      end
      @patches.touch({ release_set_id: id }, time: event.created_at)
      nil
    end

    private

    def prepare(event, preparation)
      id = event.data.fetch("release_set_id")
      attributes = { release_set_id: id, change_set_id: preparation.fetch(:change_set_id),
        ordered_members: preparation.fetch(:ordered_members), release_digest: event.metadata.fetch("release_digest"),
        preparation_policy_version: event.metadata.fetch("policy_version") }.merge(Source.evidence(event, prefix: :prepared))
      @patches.insert(attributes.merge(status: "prepared", verification_status: "unverified", integrations: [], verifications: [],
        activation: nil, compensation_request: nil, completion: nil, created_at: preparation.fetch(:created_at), updated_at: event.created_at))
      @patches.assign(attributes)
    end

    def integration(event, data)
      id = data.fetch(:release_set_id)
      introduced = data.slice(:repository_id, :member_position, :attempt_id, :attempt_number, :outcome, :failure).merge(
        observation_digest: event.metadata["observation_digest"], integration_digest: event.metadata.fetch("integration_digest"),
        policy_version: event.metadata.fetch("policy_version"), evidence_status: "attributed_unverified",
        recorded_at: timestamp(event), source: evidence(event))
      entries = upsert(value(id, :integrations, []), introduced, defaults: { merge_observation_event: nil })
      assign(id, integrations: entries, status: "integrating")
    end

    def merge_link(event, data)
      id = data.fetch(:release_set_id)
      entries = value(id, :integrations, []).map(&:dup)
      index = entries.rindex { _1.dig(:source, :event, :event_id) == event.causation_id } ||
        entries.rindex { _1.fetch(:repository_id) == data.fetch(:repository_id) }
      entries.fetch(index)[:merge_observation_event] = data.fetch(:merge_observation)
      assign(id, integrations: entries)
    end

    def verification(event, data)
      id = data.fetch(:release_set_id)
      introduced = data.slice(:attempt_number, :evidence).merge(verification_digest: event.metadata.fetch("verification_digest"),
        policy_version: event.metadata.fetch("policy_version"), evidence_status: "attributed_unverified",
        recorded_at: timestamp(event), source: evidence(event))
      entries = upsert(value(id, :verifications, []), introduced, defaults: { integration_events: [], integration_link_events: [] })
      outcome = data.fetch(:evidence).fetch(:outcome)
      assign(id, verifications: entries, verification_status: outcome, status: outcome == "passed" ? "verified" : "verifying")
    end

    def verification_link(event, data)
      id = data.fetch(:release_set_id)
      entries = value(id, :verifications, []).map(&:dup)
      entry = entries.fetch(linked_parent(entries, event))
      entry[:integration_events] = add_reference(entry.fetch(:integration_events), data.fetch(:integration_event))
      entry[:integration_link_events] = add_reference(entry.fetch(:integration_link_events, []), Source.reference(event))
      assign(id, verifications: entries)
    end

    def activation(event, data)
      id = data.fetch(:release_set_id)
      verification = value(id, :verifications, []).reverse.find { _1[:verification_digest] == event.metadata.fetch("verification_digest") }
      payload = data.slice(:activation_point).merge(verification_event: verification&.dig(:source, :event),
        verification_digest: event.metadata.fetch("verification_digest"), activation_digest: event.metadata.fetch("activation_digest"),
        policy_version: event.metadata.fetch("policy_version"), evidence_status: "attributed_unverified",
        recorded_at: timestamp(event), source: evidence(event))
      assign(id, activation: payload, status: "activated")
    end

    def compensation_request(event, data)
      id = data.fetch(:release_set_id)
      existing = value(id, :compensation_request, {})
      payload = if existing.dig(:source, :event, :event_id) == event.id
        existing
      else
        { trigger_event: nil, successful_integrations: [], integration_link_events: [] }
      end
      payload = payload.merge(data.slice(:trigger_kind, :reason)).merge(rule_version: event.metadata.fetch("rule_version"),
        requested_at: timestamp(event), source: evidence(event))
      assign(id, compensation_request: payload, status: "compensation_requested")
    end

    def compensation_link(event, data)
      id = data.fetch(:release_set_id)
      request = value(id, :compensation_request, {}).dup
      request[:successful_integrations] = add_reference(request.fetch(:successful_integrations, []), data.fetch(:integration_event))
      request[:integration_link_events] = add_reference(request.fetch(:integration_link_events, []), Source.reference(event))
      assign(id, compensation_request: request)
    end

    def repository_compensation(event, data)
      id = data.fetch(:release_set_id)
      completion = value(id, :completion, {}).dup
      entry = data.slice(:repository_id, :integration_event, :action, :external_reference).merge(
        result_digest: event.metadata.fetch("result_digest"), producer: Coordinator::Read::CommandResults::Source.document(event.metadata.fetch("producer")),
        run_id: event.metadata.fetch("run_id"), source_event_id: event.id)
      entries = completion.fetch(:compensation_evidence, []).dup
      index = entries.index { _1.fetch(:source_event_id) == event.id }
      index ? entries[index] = entry : entries << entry
      completion[:compensation_evidence] = entries
      assign(id, completion:)
    end

    def outcome(event, data)
      id = data.fetch(:release_set_id)
      completion = value(id, :completion, {}).merge(data.slice(:outcome)).merge(source_event: nil,
        completion_digest: event.metadata.fetch("completion_digest"), rule_version: event.metadata.fetch("rule_version"),
        completed_at: timestamp(event), source: evidence(event))
      completion[:compensation_evidence] ||= []
      assign(id, completion:)
    end

    def assign(id, **attributes)
      @documents.fetch(id).merge!(attributes)
      @patches.assign({ release_set_id: id }.merge(attributes))
    end

    def value(id, column, default)
      @documents.fetch(id).fetch(column, nil) || default
    end

    def upsert(entries, introduced, defaults: {})
      entries = entries.dup
      index = entries.index { _1.dig(:source, :event, :event_id) == introduced.dig(:source, :event, :event_id) }
      index ? entries[index] = entries.fetch(index).merge(introduced) : entries << defaults.merge(introduced)
      entries
    end

    def linked_parent(entries, event)
      entries.rindex do |entry|
        entry.dig(:source, :event, :event_id) == event.causation_id ||
          entry.fetch(:integration_link_events, []).any? { _1.fetch(:event_id) == event.causation_id }
      end || entries.length - 1
    end

    def add_reference(entries, reference)
      entries = entries.dup
      index = entries.index { _1.fetch(:event_id) == reference.fetch(:event_id) }
      index ? entries[index] = reference : entries << reference
      entries
    end

    def timestamp(event)
      event.created_at.utc.iso8601(6)
    end

    def evidence(event)
      { event: Source.reference(event), actor: Source.actor(event).merge(authenticated: event.metadata.fetch("actor_authenticated", false)),
        markers: event.markers, metadata: event.metadata, global_position: event.global_position,
        occurred_at: timestamp(event), persisted_at: timestamp(event), causation_id: event.causation_id, correlation_id: event.correlation_id }
    end
  end
end
