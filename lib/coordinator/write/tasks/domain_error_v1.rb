# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    module DomainErrorV1
      class ChangeSetDetails < Value
        attribute :change_set_id, Types::Identifier
      end

      class ActivationDependencyDetails < Value
        attribute :change_set_id, Types::Identifier
        attribute :dependency_id, Types::Identifier
      end

      class WorkItemDetails < Value
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
      end

      class DependencyDetails < Value
        attribute :change_set_id, Types::Identifier
        attribute :dependency_id, Types::Identifier
        attribute :producer_work_item_id, Types::Identifier
        attribute :consumer_work_item_id, Types::Identifier
      end

      class AttemptDetails < Value
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
        attribute :attempt_id, Types::Identifier
      end

      class CommandIdReusedDetails < Value
        attribute :command_id, Types::Identifier
        attribute :existing_tool_name, Types::Identifier
        attribute :existing_input_digest, Types::Sha256Digest
        attribute :requested_tool_name, Types::Identifier
        attribute :requested_input_digest, Types::Sha256Digest
      end

      class ChangeSetError < Value
        attribute :code, Types::String.enum(
          "change_set_already_exists",
          "change_set_not_found",
          "change_set_already_active",
          "change_set_has_no_criteria",
          "change_set_has_no_work_items",
          "dependency_cycle"
        )
        attribute :message, Types::String
        attribute :details, ChangeSetDetails
      end

      class ActivationDependencyError < Value
        attribute :code, Types::String.enum("dependency_endpoint_missing")
        attribute :message, Types::String
        attribute :details, ActivationDependencyDetails
      end

      class WorkItemError < Value
        attribute :code, Types::String.enum(
          "change_set_not_found",
          "change_set_not_draft",
          "work_item_already_exists",
          "work_item_limit_reached"
        )
        attribute :message, Types::String
        attribute :details, WorkItemDetails
      end

      class DependencyError < Value
        attribute :code, Types::String.enum(
          "change_set_not_found",
          "change_set_not_draft",
          "work_item_not_member",
          "dependency_self_reference",
          "dependency_id_reused",
          "dependency_limit_reached",
          "required_output_mismatch",
          "dependency_cycle"
        )
        attribute :message, Types::String
        attribute :details, DependencyDetails
      end

      class AttemptError < Value
        attribute :code, Types::String.enum(
          "change_set_not_active",
          "work_item_not_ready",
          "work_item_unavailable",
          "attempt_already_exists",
          "repository_base_mismatch"
        )
        attribute :message, Types::String
        attribute :details, AttemptDetails
      end

      class CommandIdReusedError < Value
        attribute :code, Types::String.enum("command_id_reused")
        attribute :message, Types::String
        attribute :details, CommandIdReusedDetails
      end

      Type = ChangeSetError |
             ActivationDependencyError |
             WorkItemError |
             DependencyError |
             AttemptError |
             CommandIdReusedError
    end
  end
end
