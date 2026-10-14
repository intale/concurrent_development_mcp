# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class Catalog
      TOOLS = %w[repository_register resource_resolve resource_remove skill_publish development_artifact_capture
        development_artifact_update development_artifact_classification_correct development_artifact_relation_declare].freeze
      ARTIFACT_PROPERTIES = {
        "DevelopmentArtifactScopeChanged" => "scope", "DevelopmentArtifactTitleChanged" => "title",
        "DevelopmentArtifactKindChanged" => "kind", "DevelopmentArtifactLabelAdded" => "labels",
        "DevelopmentArtifactLabelRemoved" => "labels", "DevelopmentArtifactSourceChanged" => "source",
        "DevelopmentArtifactContentChanged" => "content"
      }.freeze

      def initialize(facts:)
        @facts = facts
      end

      def call(source)
        case source.tool_name
        when "repository_register" then repository(source)
        when "resource_resolve" then resolve_resource(source)
        when "resource_remove" then remove_resource(source)
        when "skill_publish" then skill(source)
        when "development_artifact_capture" then capture(source)
        when "development_artifact_update" then update(source)
        when "development_artifact_classification_correct" then classification(source)
        when "development_artifact_relation_declare" then relation(source)
        end
      end

      private

      def repository(source)
        registration = source.event("RepositoryRegistered") || @facts.indexed(context: "DevelopmentPlanning", stream: "Repository",
          types: [ "RepositoryRegistered" ], through_position: source.terminal_event.global_position,
          marker: compound("scoped-repository-key", scope: source.input.fetch(:scope), "repository-key": source.input.fetch(:repository_key)))
        state = source.data(registration).slice(:repository_id, :scope).merge(display_name: nil, paths: [], remotes: [])
        properties = %w[RepositoryDisplayNameChanged RepositoryPathAdded RepositoryPathRemoved RepositoryRemoteAdded RepositoryRemoteRemoved]
        latest = @facts.latest(context: "DevelopmentPlanning", stream: "Repository", types: [ "RepositoryRegistered", *properties ],
          marker: "repository:#{registration.stream.stream_id}", through_position: source.terminal_event.global_position)
        @facts.history(:repository, registration.stream.stream_id, properties, maximum_count: 1_024,
          to_revision: latest.stream_revision).each do |event|
          case event.type
          when "RepositoryDisplayNameChanged" then state[:display_name] = event.data.fetch("display_name")
          when "RepositoryPathAdded" then state[:paths] |= [ event.data.fetch("path") ]
          when "RepositoryPathRemoved" then state[:paths] -= [ event.data.fetch("path") ]
          when "RepositoryRemoteAdded" then state[:remotes] |= [ event.data.fetch("remote") ]
          when "RepositoryRemoteRemoved" then state[:remotes] -= [ event.data.fetch("remote") ]
          end
        end
        source.presentation(source.persisted_events.empty? ?
          "Canonical Repository registration already exists for the exact scope and key." :
          "Repository registered under its exact coordination scope and key.", state.merge(registered_at: source.timestamp(registration)))
      end

      def resolve_resource(source)
        registration = source.event("ResourceRegistered")
        binding = source.event("ResourceBound")
        outcome = registration ? "registered" : (binding ? "reactivated" : "existing")
        binding ||= @facts.latest(context: "DevelopmentCoordination", stream: "Resource", types: [ "ResourceBound" ],
          marker: Coordinator::Shared::ResourceMarkerCodec.new.current_path(repository_id: source.input.fetch(:repository_id),
            normalized_path: source.input.fetch(:path).unicode_normalize(:nfc)), through_position: source.terminal_event.global_position)
        registration ||= @facts.first(:resource, binding.stream.stream_id, "ResourceRegistered")
        summary = { "registered" => "Resource identity registered and bound.", "reactivated" => "Existing Resource identity reactivated.",
          "existing" => "Existing Resource identity resolved." }.fetch(outcome)
        source.presentation(summary, source.data(registration).merge(outcome:, registered_at: source.timestamp(registration), bound_at: source.timestamp(binding)))
      end

      def remove_resource(source)
        registration = @facts.first(:resource, source.input.fetch(:resource_id), "ResourceRegistered")
        unbound = source.event("ResourceUnbound")
        source.presentation(unbound ? "Resource binding removed." : "Resource binding was already inactive.",
          source.data(registration).merge(outcome: unbound ? "removed" : "already_inactive", reason: source.input.fetch(:reason),
            unbound_at: unbound ? source.timestamp(unbound) : source.completed_at))
      end

      def skill(source)
        registration = @facts.indexed(context: "AgentKnowledge", stream: "Skill", types: [ "SkillRegistered" ],
          marker: compound("skill-natural-key", scope: source.input.fetch(:scope), name: source.input.fetch(:name)),
          through_position: source.terminal_event.global_position)
        publication = source.event("SkillRevisionPublished") || @facts.at(:skill, registration.stream.stream_id, source.input.fetch(:expected_revision))
        source.presentation(source.event("SkillRevisionPublished") ? "Skill revision published as cohesive immutable facts." :
          "The requested Skill revision content is already published.", source.values(:name, :scope, :content_digest).merge(
          skill_id: publication.data.fetch("skill_id"), revision: publication.data.fetch("revision"),
          asset_count: source.input.fetch(:assets).length, publication_event: source.reference(publication), published_at: source.timestamp(publication)
        ))
      end

      def capture(source)
        artifact = source.input.fetch(:artifact)
        created, recorded = source.event("DevelopmentArtifactCreated"), source.event("DevelopmentArtifactObservationRecorded")
        linked = source.event("DevelopmentArtifactObservationFactLinked")
        artifact_id = linked&.data&.fetch("artifact_id") || artifact.fetch(:artifact_id)
        observation_id = recorded&.stream&.stream_id || artifact.fetch(:observation_id)
        outcome = created ? "captured" : (recorded ? "observed" : "existing")
        summary = { "captured" => "Development Artifact content and observation captured.",
          "observed" => "Development Artifact observation captured for existing content.",
          "existing" => "Development Artifact observation already exists." }.fetch(outcome)
        source.presentation(summary, artifact.slice(:scope, :kind).merge(
          artifact_id:, observation_id:, classification_revision: 1, content_sha256: artifact.fetch(:content).fetch(:content_sha256),
          byte_size: artifact.fetch(:content).fetch(:byte_size), outcome:, recorded_at: (recorded || created) ? source.timestamp(recorded || created) : source.completed_at
        ), next_actions: [ source.action("development_artifact_get", artifact_id:, observation_id: artifact.fetch(:observation_id)) ])
      end

      def update(source)
        changed_properties = source.persisted_events.filter_map { ARTIFACT_PROPERTIES[_1.type] }.uniq
        latest = source.persisted_events.last
        outcome = changed_properties.empty? ? "existing" : "updated"
        source.presentation(outcome == "updated" ? "Development Artifact properties updated as granular facts." :
          "Development Artifact already has the requested properties.", source.values(:artifact_id).merge(
          resulting_stream_revision: latest&.stream_revision || source.input.fetch(:expected_revision), changed_properties:, outcome:,
          updated_at: latest ? source.timestamp(latest) : source.completed_at
        ), next_actions: [ source.action("development_artifact_get", **source.values(:artifact_id)) ])
      end

      def classification(source)
        history = @facts.history(:development_artifact_observation, source.input.fetch(:observation_id),
          %w[DevelopmentArtifactObservationRecorded DevelopmentArtifactObservationFactLinked DevelopmentArtifactClassificationCorrectionRecorded], maximum_count: 1_024)
          .select { _1.global_position <= source.terminal_event.global_position }
        corrected = source.event("DevelopmentArtifactClassificationCorrectionRecorded")
        artifact_id = (corrected || history.find { _1.type == "DevelopmentArtifactObservationFactLinked" }).data.fetch("artifact_id")
        revision = corrected&.data&.fetch("classification_revision") ||
          history.reverse.find { _1.type == "DevelopmentArtifactClassificationCorrectionRecorded" }&.data&.fetch("classification_revision") || 1
        source.presentation(corrected ? "Development Artifact observation classification corrected." :
          "Development Artifact observation classification is already current.", source.values(:observation_id, :title, :kind, :labels).merge(
          artifact_id:, classification_revision: revision, outcome: corrected ? "corrected" : "existing",
          corrected_at: corrected ? source.timestamp(corrected) : source.completed_at
        ), next_actions: [ source.action("development_artifact_get", artifact_id:, observation_id: source.input.fetch(:observation_id)) ])
      end

      def relation(source)
        declaration = source.event("DevelopmentArtifactRelationDeclared") || relation_registration(source)
        fact = source.data(declaration)
        supersession = source.event("DevelopmentArtifactRelationSuperseded")
        outcome = supersession ? "superseded" : (source.persisted_events.empty? ? "existing" : "declared")
        source.presentation({ "declared" => "Development Artifact relation declared.", "superseded" => "Development Artifact relation superseded.",
          "existing" => "Development Artifact relation already exists." }.fetch(outcome), fact.slice(:relation_id, :source_artifact_id, :relation).merge(
          target: { kind: fact.fetch(:target_kind), id: fact.fetch(:target_id), status: fact.fetch(:target_kind) == "external" ? "unverified" : "verified", name: nil, scope: nil },
          superseded_relation_id: supersession&.data&.fetch("relation_id"), outcome:, declared_at: source.timestamp(declaration),
          superseded_at: supersession && source.timestamp(supersession)
        ), next_actions: [ source.action("development_artifact_get", artifact_id: fact.fetch(:source_artifact_id)) ])
      end

      def relation_registration(source)
        relation = source.input.fetch(:artifact_relation)
        components = [ "source-artifact-id:#{relation.fetch(:source_artifact_id)}", "relation:#{relation.fetch(:relation)}" ]
        builder = Coordinator::Shared::CanonicalMarkerComponentBuilder.new
        components += builder.call(dimension: "target", value: relation.fetch(:target).slice(:kind, :id))
        attributes = relation.fetch(:relation_attributes).slice(:path)
        attributes.merge!(relation.fetch(:relation_attributes).slice(:fragment, :normalized_locator).compact)
        components += builder.call(dimension: "attributes", value: attributes)
        marker = Coordinator::Shared::Markers::CodecV2.encode(purpose: "development-artifact-relation-natural-key",
          components: components.map { |component| dimension, _, value = component.partition(":"); { dimension:, value: } })
        @facts.indexed(context: "DevelopmentMemory", stream: "DevelopmentArtifactRelation", types: [ "DevelopmentArtifactRelationDeclared" ],
          marker:, through_position: source.terminal_event.global_position)
      end

      def compound(purpose, **values)
        Coordinator::Shared::Markers::CodecV2.encode(purpose:, components: values.map { |dimension, value| { dimension: dimension.to_s, value: } })
      end
    end
  end
end
