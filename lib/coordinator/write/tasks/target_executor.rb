# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class TargetExecutor
      def initialize(
        event_store:,
        create_change_set: Operations::ExecuteCreateChangeSet.new(event_store:),
        create_work_item: Operations::ExecuteCreateWorkItem.new(event_store:),
        declare_work_item_dependency: Operations::ExecuteDeclareWorkItemDependency.new(event_store:),
        activate_change_set: Operations::ExecuteActivateChangeSet.new(event_store:),
        acquire_work_item: Operations::ExecuteAcquireWorkItem.new(event_store:),
        reserve_write_set: Operations::ExecuteReserveWriteSet.new(event_store:),
        expand_write_set: Operations::ExecuteExpandWriteSet.new(event_store:),
        renew_lease_set: Operations::ExecuteRenewLeaseSet.new(event_store:)
      )
        @create_change_set = create_change_set
        @create_work_item = create_work_item
        @declare_work_item_dependency = declare_work_item_dependency
        @activate_change_set = activate_change_set
        @acquire_work_item = acquire_work_item
        @reserve_write_set = reserve_write_set
        @expand_write_set = expand_write_set
        @renew_lease_set = renew_lease_set
      end

      def call(command, caused_by:)
        case command
        when Commands::CreateChangeSet
          @create_change_set.call_command(command, caused_by:)
        when Commands::CreateWorkItem
          @create_work_item.call_command(command, caused_by:)
        when Commands::DeclareWorkItemDependency
          @declare_work_item_dependency.call_command(command, caused_by:)
        when Commands::ActivateChangeSet
          @activate_change_set.call_command(command, caused_by:)
        when Commands::AcquireWorkItem
          @acquire_work_item.call_command(command, caused_by:)
        when Commands::ReserveWriteSet
          @reserve_write_set.call_command(command, caused_by:)
        when Commands::ExpandWriteSet
          @expand_write_set.call_command(command, caused_by:)
        when Commands::RenewLeaseSet
          @renew_lease_set.call_command(command, caused_by:)
        end
      end
    end
  end
end
