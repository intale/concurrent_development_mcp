# frozen_string_literal: true

module Coordinator
  module Domain
    module ChangeSets
      class Dependency < Value
        attribute :dependency_id, Types::Identifier
        attribute :producer_work_item_id, Types::Identifier
        attribute :consumer_work_item_id, Types::Identifier
        attribute :dependency_kind, Types::DependencyKind
        attribute :required_output, RequiredOutput.optional
      end
    end
  end
end
