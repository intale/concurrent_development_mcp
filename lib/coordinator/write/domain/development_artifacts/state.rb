# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class State < Value
        Created = Types.Instance(Events::DevelopmentArtifactCreatedV1)
        ScopeChange = Types.Instance(Events::DevelopmentArtifactScopeChangedV1)
        TitleChange = Types.Instance(Events::DevelopmentArtifactTitleChangedV1)
        KindChange = Types.Instance(Events::DevelopmentArtifactKindChangedV1)
        LabelAddition = Types.Instance(Events::DevelopmentArtifactLabelAddedV1)
        LabelRemoval = Types.Instance(Events::DevelopmentArtifactLabelRemovedV1)
        SourceChange = Types.Instance(Events::DevelopmentArtifactSourceChangedV1)
        ContentChange = Types.Instance(Events::DevelopmentArtifactContentChangedV1)

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
          new(labels: [])
        end

        def self.reduce(events, metadata_by_event: {})
          created = nil
          scope = title = kind = source = content = nil
          content_metadata = source_collector = nil
          labels = []

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
            else
              raise InvalidDevelopmentArtifactHistory, "Unexpected Artifact event #{event.class.name}"
            end
          end

          new(
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
      end
    end
  end
end
