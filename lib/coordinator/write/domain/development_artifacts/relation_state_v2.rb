# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class RelationStateV2 < Value
        Declaration = Types.Instance(Events::DevelopmentArtifactRelationDeclaredV2)
        Supersession = Types.Instance(Events::DevelopmentArtifactRelationSupersededV2)

        attribute :declaration, Declaration.optional
        attribute :supersession, Supersession.optional

        def self.initial
          new(declaration: nil, supersession: nil)
        end

        def self.reduce(events)
          declaration = nil
          supersession = nil
          events.each do |event|
            case event
            when Events::DevelopmentArtifactRelationDeclaredV2
              raise InvalidDevelopmentArtifactHistory, "Relation was declared more than once" if declaration

              declaration = event
            when Events::DevelopmentArtifactRelationSupersededV2
              raise InvalidDevelopmentArtifactHistory, "Relation supersession precedes declaration" unless declaration
              raise InvalidDevelopmentArtifactHistory, "Relation was superseded more than once" if supersession
              unless event.relation_id == declaration.relation_id
                raise InvalidDevelopmentArtifactHistory, "Relation supersession targets another relation"
              end

              supersession = event
            else
              raise InvalidDevelopmentArtifactHistory, "Unexpected relation event #{event.class.name}"
            end
          end

          new(declaration:, supersession:)
        end

        def active?
          declaration && !supersession
        end
      end
    end
  end
end
