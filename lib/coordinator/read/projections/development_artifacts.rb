# frozen_string_literal: true

module Coordinator::Read::Projections
  class DevelopmentArtifacts
    def initialize(artifacts:, observations:, links:, relations:, supersessions:, artifact_labels: {}, observation_labels: {})
      @artifacts, @observations, @links, @relations, @supersessions = artifacts, observations, links, relations, supersessions
      @artifact_labels, @observation_labels = artifact_labels, observation_labels
    end

    def apply(event, observed_fact: nil)
      data = Coordinator::Read::CommandResults::Source.document(event.data)
      case event.type
      when "DevelopmentArtifactCreated"
        attributes = data.slice(:artifact_id).merge(Source.evidence(event, prefix: :captured), stream_revision: event.stream_revision,
          observed_sequence: event.global_position)
        @artifacts.insert(attributes.merge(labels: [], active_relations_number: 0, lifetime_relations_number: 0,
          created_at: event.created_at, updated_at: event.created_at))
        @artifacts.assign(attributes)
        @artifacts.touch(data.slice(:artifact_id), time: event.created_at)
      when "DevelopmentArtifactObservationRecorded" then observation(event, data)
      when "DevelopmentArtifactObservationFactLinked" then link(event, data, observed_fact)
      when "DevelopmentArtifactClassificationCorrectionRecorded" then classification(event, data)
      when "DevelopmentArtifactRelationDeclared" then relation(event, data)
      when "DevelopmentArtifactRelationSuperseded" then supersession(event, data)
      when "DevelopmentArtifactRelationsNumberChanged"
        @artifacts.assign(data.slice(:artifact_id, :active_relations_number, :lifetime_relations_number))
        @artifacts.touch(data.slice(:artifact_id), time: event.created_at)
      else
        attributes = properties(event, id: data.fetch(:artifact_id), labels: @artifact_labels)
        @artifacts.assign({ artifact_id: data.fetch(:artifact_id), stream_revision: event.stream_revision }.merge(attributes))
        @artifacts.touch(data.slice(:artifact_id), time: event.created_at)
      end
      nil
    end

    private

    def observation(event, data)
      id = data.fetch(:observation_id)
      seed_observation(id, event: event, defaults: Source.evidence(event, prefix: :classified))
      @observations.assign(data.slice(:observation_id).merge(Source.evidence(event, prefix: :observed),
        current_global_position: event.global_position, observed_sequence: event.global_position))
      @observations.touch(data.slice(:observation_id), time: event.created_at)
    end

    def classification(event, data)
      id = data.fetch(:observation_id)
      seed_observation(id, event:)
      @observations.assign(data.slice(:observation_id, :artifact_id, :classification_revision).merge(
        classification_reason: data.fetch(:reason), **Source.evidence(event, prefix: :classified),
        current_global_position: event.global_position, observed_sequence: event.global_position))
      @observations.touch(data.slice(:observation_id), time: event.created_at)
    end

    def link(event, data, fact)
      id = data.fetch(:observation_id)
      attributes = { link_event_id: event.id, observation_id: id, artifact_id: data.fetch(:artifact_id), role: data.fetch(:role),
        observed_fact_event: Source.reference(fact), observed_fact_event_id: fact.id, observed_fact_data: fact.data,
        observed_fact_metadata: fact.metadata, observed_fact_created_at: fact.created_at }.merge(Source.evidence(event, prefix: :link))
      @links.insert(attributes.merge(created_at: event.created_at, updated_at: event.created_at))
      @links.assign(attributes)
      @links.touch({ link_event_id: event.id }, time: event.created_at)
      seed_observation(id, event:)
      @observations.assign({ observation_id: id, artifact_id: data.fetch(:artifact_id), current_global_position: event.global_position,
        observed_sequence: event.global_position }.merge(properties(fact, id:, labels: @observation_labels)))
      @observations.touch({ observation_id: id }, time: event.created_at)
    end

    def seed_observation(id, event:, defaults: {})
      @observations.insert({ observation_id: id, classification_revision: 1, classification_reason: nil, labels: [],
        current_global_position: event.global_position, observed_sequence: event.global_position,
        created_at: event.created_at, updated_at: event.created_at }.merge(defaults))
    end

    def properties(event, id:, labels:)
      data = Coordinator::Read::CommandResults::Source.document(event.data)
      case event.type
      when "DevelopmentArtifactScopeChanged" then data.slice(:scope)
      when "DevelopmentArtifactTitleChanged" then data.slice(:title)
      when "DevelopmentArtifactKindChanged" then data.slice(:kind)
      when "DevelopmentArtifactLabelAdded", "DevelopmentArtifactLabelRemoved"
        current = labels.fetch(id, []).dup
        label = data.fetch(:label)
        updated = event.type == "DevelopmentArtifactLabelAdded" ? (current | [ label ]).sort : current - [ label ]
        labels[id] = updated
        { labels: updated }
      when "DevelopmentArtifactSourceChanged"
        { source_kind: data.fetch(:source_kind), source_locator: data.fetch(:locator), source_revision: data.fetch(:revision),
          source_observed_at: data.fetch(:observed_at), source_collector: event.metadata["collector"] }
      when "DevelopmentArtifactContentChanged"
        encoding = event.metadata.fetch("encoding")
        { content_encoding: encoding, content_media_type: event.metadata.fetch("media_type"),
          content_text: encoding == "utf-8" ? data.fetch(:content) : nil, content_base64: encoding == "binary" ? data.fetch(:content) : nil,
          content_sha256: event.metadata.fetch("content_sha256"), content_byte_size: event.metadata.fetch("byte_size") }
      else {}
      end
    end

    def relation(event, data)
      attributes = data.merge(target_status: data.fetch(:target_kind) == "external" ? "unverified" : "verified",
        observed_sequence: event.global_position).merge(Source.evidence(event, prefix: :declared))
      @relations.insert(attributes.merge(created_at: event.created_at, updated_at: event.created_at))
      @relations.assign(attributes)
      @relations.touch(data.slice(:relation_id), time: event.created_at)
    end

    def supersession(event, data)
      attributes = data.except(:relation_id).merge(superseded_relation_id: data.fetch(:relation_id), observed_sequence: event.global_position)
        .merge(Source.evidence(event, prefix: :superseded))
      @supersessions.insert(attributes.merge(created_at: event.created_at, updated_at: event.created_at))
      @supersessions.assign(attributes)
      @supersessions.touch(attributes.slice(:superseded_relation_id), time: event.created_at)
    end
  end
end
