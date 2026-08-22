# frozen_string_literal: true

module Coordinator::Read
  module Projections
    class CoordContextStateV1 < Value
      class ChangeSet < Value
        attribute :change_set_id, Types::Identifier
        attribute :goal, Types::Goal
        attribute :acceptance_criteria, Types::StateAcceptanceCriteria
        attribute :status, Types::String.enum("planning", "active")
        attribute :created_at, Types::Timestamp
        attribute :activated_at, Types::Timestamp.optional
      end

      class WorkItem < Value
        attribute :work_item_id, Types::Identifier
        attribute :change_set_id, Types::Identifier
        attribute :repository_id, Types::RepositoryId
        attribute :goal, Types::Goal
        attribute :acceptance_criteria, Types::WorkItemStateAcceptanceCriteria
        attribute :competitive_mode, Types::Strict::Bool
        attribute :status, Types::String.enum("planned", "ready", "acquired")
        attribute :active_attempt_id, Types::Identifier.optional
        attribute :active_agent_id, Types::Identifier.optional
        attribute :created_at, Types::Timestamp
        attribute :made_ready_at, Types::Timestamp.optional
        attribute :acquired_at, Types::Timestamp.optional
      end

      class Dependency < Value
        attribute :dependency_id, Types::Identifier
        attribute :producer_work_item_id, Types::Identifier
        attribute :consumer_work_item_id, Types::Identifier
        attribute :dependency_kind, Types::DependencyKind
        attribute :required_output, Coordinator::Write::RequiredOutput.optional
        attribute :declared_at, Types::Timestamp
      end

      class Attempt < Value
        attribute :attempt_id, Types::Identifier
        attribute :change_set_id, Types::Identifier
        attribute :work_item_id, Types::Identifier
        attribute :agent_id, Types::Identifier
        attribute :base_snapshots, Types::Array.of(Coordinator::Write::RepositorySnapshotV1).constrained(size: 1)
        attribute :status, Types::String.enum("authorized", "started")
        attribute :authorized_at, Types::Timestamp
        attribute :started_at, Types::Timestamp.optional
      end

      attribute :schema, Types::String.enum("coord-context/v1")
      attribute :change_set, ChangeSet.optional
      attribute :work_item_ids, Types::WorkItemIds
      attribute :work_items, Types::Array.of(WorkItem).constrained(max_size: 100)
      attribute :dependencies, Types::Array.of(Dependency).constrained(max_size: 500)
      attribute :attempts, Types::Array.of(Attempt).constrained(max_size: 100)
      attribute :candidate_checkpoints, Types::Array.constrained(size: 0)

      def self.initial
        new(
          schema: "coord-context/v1",
          change_set: nil,
          work_item_ids: [],
          work_items: [],
          dependencies: [],
          attempts: [],
          candidate_checkpoints: []
        )
      end
    end
  end
end
