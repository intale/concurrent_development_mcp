# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemDependencySatisfiedV2 < Base
      contract type: "WorkItemDependencySatisfied", version: 2

      attribute :dependency_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :producer_work_item_id, Types::Identifier
      attribute :consumer_work_item_id, Types::Identifier
      attribute :dependency_kind, Types::DependencyKind
      attribute :required_output, RequiredOutput.optional
      attribute :source, EventReference
    end
  end
end
