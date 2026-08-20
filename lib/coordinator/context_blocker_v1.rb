# frozen_string_literal: true

module Coordinator
  class ContextBlockerV1 < Value
    attribute :code, Types::String.enum("dependency_unmet")
    attribute :dependency_id, Types::Identifier
    attribute :producer_work_item_id, Types::Identifier
    attribute :consumer_work_item_id, Types::Identifier
    attribute :dependency_kind, Types::DependencyKind
  end
end
