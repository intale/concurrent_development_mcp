# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ChangeSets
      class DependencySatisfaction < Value
        attribute :dependency_id, Types::Identifier
        attribute :source_event, EventReference
        attribute :satisfied_at, Types::Timestamp.optional.default(nil)
      end
    end
  end
end
