# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemDependencySatisfiedV1 < Base
      contract type: "WorkItemDependencySatisfied", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :dependency_id, Types::Identifier
      attribute :producer_work_item_id, Types::Identifier
      attribute :consumer_work_item_id, Types::Identifier
      attribute :dependency_kind, Types::DependencyKind
      attribute :required_output, RequiredOutput.optional
      attribute :source_event, EventReference
      attribute :rule_version, Types::String.enum("dependency-satisfaction/v1")
      attribute :satisfied_at, Types::Timestamp
    end
  end
end
