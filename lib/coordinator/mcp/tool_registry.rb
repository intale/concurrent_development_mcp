# frozen_string_literal: true

module Coordinator
  module Mcp
    module ToolRegistry
      module_function

      def all
        [
          Tools::CoordContext,
          Tools::OperationGet,
          Tools::ChangeSetCreate,
          Tools::WorkItemCreate,
          Tools::WorkItemDependencyDeclare,
          Tools::ChangeSetActivate,
          Tools::WorkItemAcquire,
          Tools::WriteSetReserve,
          Tools::WriteSetExpand,
          Tools::LeaseRenew
        ].freeze
      end
    end
  end
end
