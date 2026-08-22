# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class DeclareWorkItemDependency < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :change_set_id, Types::Identifier
      attribute :dependency_id, Types::Identifier
      attribute :producer_work_item_id, Types::Identifier
      attribute :consumer_work_item_id, Types::Identifier
      attribute :dependency_kind, Types::DependencyKind
      attribute :required_output, RequiredOutput.optional
    end
  end
end
