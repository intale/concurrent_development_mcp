# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class State < Value
        Capture = Types.Instance(Events::DevelopmentArtifactCapturedV1) |
                  Types.Instance(Events::DevelopmentArtifactCapturedV2)
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

        def self.initial
          new(capture: nil, relations: [], supersessions: [])
        end

        def self.reduce(events)
          capture = nil
          relations = []
          supersessions = []
          relation_ids = {}
          superseded_relation_ids = {}

          events.each do |event|
            case event
            when Events::DevelopmentArtifactCapturedV1, Events::DevelopmentArtifactCapturedV2
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

          new(capture:, relations:, supersessions:)
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
