# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class State < Value
        Capture = Types.Instance(Events::DevelopmentArtifactCapturedV1)
        Relation = Types.Instance(Events::DevelopmentArtifactRelationDeclaredV1)

        attribute :capture, Capture.optional
        attribute :relations,
                  Types::Array.of(Relation).constrained(
                    max_size: Types::DEVELOPMENT_ARTIFACT_RELATION_MAXIMUM_COUNT
                  )

        def self.initial
          new(capture: nil, relations: [])
        end

        def self.reduce(events)
          capture = nil
          relations = []
          relation_ids = {}

          events.each do |event|
            case event
            when Events::DevelopmentArtifactCapturedV1
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
            else
              raise InvalidDevelopmentArtifactHistory, "Unexpected Artifact event #{event.class.name}"
            end
          end

          new(capture:, relations:)
        end
      end
    end
  end
end
