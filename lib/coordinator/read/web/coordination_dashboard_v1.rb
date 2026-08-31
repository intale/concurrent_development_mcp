# frozen_string_literal: true

module Coordinator::Read::Web
  class CoordinationDashboardV1 < Coordinator::Shared::Value
    class Project < Coordinator::Shared::Value
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :scope, Coordinator::Shared::Types::String
      attribute :display_name, Coordinator::Shared::Types::String.optional
    end

    class ChangeSet < Coordinator::Shared::Value
      attribute :change_set_id, Coordinator::Shared::Types::String
      attribute :goal, Coordinator::Shared::Types::String
      attribute :acceptance_criteria, Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::String)
      attribute :domain_status, Coordinator::Shared::Types::String
      attribute :work_item_count, Coordinator::Shared::Types::Integer
      attribute :running_work_item_count, Coordinator::Shared::Types::Integer
      attribute :open_work_item_count, Coordinator::Shared::Types::Integer
      attribute :last_processed_at, Coordinator::Shared::Types::String
    end

    class WorkItem < Coordinator::Shared::Value
      attribute :work_item_id, Coordinator::Shared::Types::String
      attribute :change_set_id, Coordinator::Shared::Types::String
      attribute :repository_id, Coordinator::Shared::Types::UuidV7
      attribute :goal, Coordinator::Shared::Types::String
      attribute :acceptance_criteria, Coordinator::Shared::Types::Array.of(Coordinator::Shared::Types::String)
      attribute :competitive_mode, Coordinator::Shared::Types::Strict::Bool
      attribute :domain_status, Coordinator::Shared::Types::String
      attribute :presentation_status, Coordinator::Shared::Types::String
      attribute :active_attempt_id, Coordinator::Shared::Types::String.optional
      attribute :active_agent_id, Coordinator::Shared::Types::String.optional
      attribute :attempt_status, Coordinator::Shared::Types::String.optional
      attribute :attempt_authorized_at, Coordinator::Shared::Types::String.optional
      attribute :attempt_started_at, Coordinator::Shared::Types::String.optional
      attribute :attempt_terminal_at, Coordinator::Shared::Types::String.optional
      attribute :created_at, Coordinator::Shared::Types::String
      attribute :made_ready_at, Coordinator::Shared::Types::String.optional
      attribute :acquired_at, Coordinator::Shared::Types::String.optional
      attribute :completed_at, Coordinator::Shared::Types::String.optional
      attribute :last_processed_at, Coordinator::Shared::Types::String
    end

    class Dependency < Coordinator::Shared::Value
      attribute :dependency_id, Coordinator::Shared::Types::String
      attribute :producer_work_item_id, Coordinator::Shared::Types::String
      attribute :consumer_work_item_id, Coordinator::Shared::Types::String
      attribute :producer_repository_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :consumer_repository_id, Coordinator::Shared::Types::UuidV7.optional
      attribute :dependency_kind, Coordinator::Shared::Types::String
      attribute :blocking, Coordinator::Shared::Types::Strict::Bool
      attribute :declared_at, Coordinator::Shared::Types::String
      attribute :satisfied_at, Coordinator::Shared::Types::String.optional
      attribute :last_processed_at, Coordinator::Shared::Types::String
    end

    class ChangeSetPage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(ChangeSet)
      attribute :next_offset, Coordinator::Shared::Types::Integer.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class WorkItemPage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(WorkItem)
      attribute :next_offset, Coordinator::Shared::Types::Integer.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    class DependencyPage < Coordinator::Shared::Value
      attribute :items, Coordinator::Shared::Types::Array.of(Dependency)
      attribute :next_offset, Coordinator::Shared::Types::Integer.optional
      attribute :has_more, Coordinator::Shared::Types::Strict::Bool
    end

    attribute :project, Project
    attribute :change_sets, ChangeSetPage
    attribute :work_items, WorkItemPage
    attribute :dependencies, DependencyPage
  end
end
