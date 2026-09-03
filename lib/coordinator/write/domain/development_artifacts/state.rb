# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class State < Value
        Capture = Types.Instance(Events::DevelopmentArtifactCapturedV2)
        Created = Types.Instance(Events::DevelopmentArtifactCreatedV1)
        ScopeChange = Types.Instance(Events::DevelopmentArtifactScopeChangedV1)
        TitleChange = Types.Instance(Events::DevelopmentArtifactTitleChangedV1)
        KindChange = Types.Instance(Events::DevelopmentArtifactKindChangedV1)
        LabelAddition = Types.Instance(Events::DevelopmentArtifactLabelAddedV1)
        LabelRemoval = Types.Instance(Events::DevelopmentArtifactLabelRemovedV1)
        SourceChange = Types.Instance(Events::DevelopmentArtifactSourceChangedV1)
        ContentChange = Types.Instance(Events::DevelopmentArtifactContentChangedV1)
        Relation = Types.Instance(Events::DevelopmentArtifactRelationDeclaredV1)
        Supersession = Types.Instance(Events::DevelopmentArtifactRelationSupersededV1)

        attribute :capture, Capture.optional
        attribute :relations,
                  Types::Array.of(Relation).constrained(
                    max_size: Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT
                  )
        attribute :supersessions,
                  Types::Array.of(Supersession).constrained(
                    max_size: Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT
                  )

        attribute? :created, Created.optional
        attribute? :scope, ScopeChange.optional
        attribute? :title, TitleChange.optional
        attribute? :kind, KindChange.optional
        attribute? :labels, Types::DevelopmentArtifactLabels.optional
        attribute? :source, SourceChange.optional
        attribute? :content, ContentChange.optional
        attribute? :content_metadata, Coordinator::Write::DevelopmentArtifacts::ContentDescriptorV1.optional
        attribute? :source_collector, Types::DevelopmentArtifactCollector.optional

        def self.initial
          new(capture: nil, relations: [], supersessions: [])
        end

        def self.reduce(events, metadata_by_event: {})
          capture = nil
          relations = []
          supersessions = []
          created = nil
          scope = title = kind = source = content = nil
          content_metadata = source_collector = nil
          labels = []
          relation_ids = {}
          superseded_relation_ids = {}

          events.each do |event|
            case event
            when Events::DevelopmentArtifactCreatedV1
              raise InvalidDevelopmentArtifactHistory, "Artifact was created more than once" if created

              created = event
            when Events::DevelopmentArtifactScopeChangedV1
              ensure_created!(created)
              scope = event
            when Events::DevelopmentArtifactTitleChangedV1
              ensure_created!(created)
              title = event
            when Events::DevelopmentArtifactKindChangedV1
              ensure_created!(created)
              kind = event
            when Events::DevelopmentArtifactLabelAddedV1
              ensure_created!(created)
              labels << event.label unless labels.include?(event.label)
            when Events::DevelopmentArtifactLabelRemovedV1
              ensure_created!(created)
              labels.delete(event.label)
            when Events::DevelopmentArtifactSourceChangedV1
              ensure_created!(created)
              source = event
              source_collector = metadata_by_event[event.object_id]&.fetch("collector", nil)
            when Events::DevelopmentArtifactContentChangedV1
              ensure_created!(created)
              content = event
              metadata = metadata_by_event[event.object_id] || {}
              if metadata.values_at("encoding", "media_type", "byte_size", "content_sha256").all?
                content_metadata = Coordinator::Write::DevelopmentArtifacts::ContentDescriptorV1.new(
                  encoding: metadata.fetch("encoding"), media_type: metadata.fetch("media_type"),
                  byte_size: metadata.fetch("byte_size"), content_sha256: metadata.fetch("content_sha256")
                )
              end
            when Events::DevelopmentArtifactCapturedV2
              raise InvalidDevelopmentArtifactHistory, "Artifact was captured more than once" if capture

              capture = event
            when Events::DevelopmentArtifactRelationDeclaredV1
              raise InvalidDevelopmentArtifactHistory, "Artifact relation precedes capture" unless capture
              relation_id = event.artifact_relation.relation_id
              if relation_ids.key?(relation_id)
                raise InvalidDevelopmentArtifactHistory, "Artifact relation identity is duplicated"
              end

              relation_ids[relation_id] = true
              relations << event
            when Events::DevelopmentArtifactRelationSupersededV1
              raise InvalidDevelopmentArtifactHistory, "Artifact relation supersession precedes capture" unless capture
              superseded_id = event.superseded_relation_id
              replacement_id = event.replacement_relation_id
              unless relation_ids.key?(superseded_id) && relation_ids.key?(replacement_id)
                raise InvalidDevelopmentArtifactHistory, "Artifact relation supersession references an unknown relation"
              end
              if superseded_id == replacement_id
                raise InvalidDevelopmentArtifactHistory, "Artifact relation cannot supersede itself"
              end
              if superseded_relation_ids.key?(superseded_id)
                raise InvalidDevelopmentArtifactHistory, "Artifact relation was superseded more than once"
              end
              if superseded_relation_ids.key?(replacement_id)
                raise InvalidDevelopmentArtifactHistory, "Superseded Artifact relation cannot be a replacement"
              end

              superseded_relation_ids[superseded_id] = event
              supersessions << event
            else
              raise InvalidDevelopmentArtifactHistory, "Unexpected Artifact event #{event.class.name}"
            end
          end

          new(
            capture:,
            relations:,
            supersessions:,
            created:,
            scope:,
            title:,
            kind:,
            labels:,
            source:,
            content:,
            content_metadata:,
            source_collector:
          )
        end

        def self.ensure_created!(created)
          return if created

          raise InvalidDevelopmentArtifactHistory, "Artifact property fact precedes creation"
        end

        def relation(relation_id)
          relations.find { _1.artifact_relation.relation_id == relation_id }
        end

        def supersession_for(relation_id)
          supersessions.find { _1.superseded_relation_id == relation_id }
        end

        def active_relation(relation_id)
          declaration = relation(relation_id)
          declaration unless declaration && supersession_for(relation_id)
        end

        def active_relations
          relations.reject { supersession_for(_1.artifact_relation.relation_id) }
        end
      end
    end
  end
end
