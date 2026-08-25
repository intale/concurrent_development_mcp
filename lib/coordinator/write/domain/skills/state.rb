# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Skills
      class State < Value
        Publication = Types.Instance(Events::SkillRevisionPublishedV1)

        attribute :publication, Publication.optional

        def self.initial
          new(publication: nil)
        end

        def self.reduce(events)
          publication = events.max_by(&:revision)
          new(publication:)
        end

        def current_revision
          publication&.revision || 0
        end
      end
    end
  end
end
