# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Attempts
      class State < Value
        Snapshot = Types.Instance(RepositorySnapshotV1)

        attribute :attempt_id, Types::Identifier.optional
        attribute :change_set_id, Types::Identifier.optional
        attribute :work_item_id, Types::Identifier.optional
        attribute :agent_id, Types::Identifier.optional
        attribute :base_snapshots, Types::Array.of(Snapshot).constrained(max_size: 1)
        attribute :lease_set_id, Types::UuidV7.optional
        attribute :status, Types::String.enum("absent", "authorized", "active")

        def self.initial
          new(
            attempt_id: nil,
            change_set_id: nil,
            work_item_id: nil,
            agent_id: nil,
            base_snapshots: [],
            lease_set_id: nil,
            status: "absent"
          )
        end

        def self.reduce(events)
          events.reduce(initial) { |state, event| state.apply(event) }
        end

        def absent?
          status == "absent"
        end

        def apply(event)
          case event
          when Events::AttemptAuthorizedV1
            self.class.new(
              attempt_id: event.attempt_id,
              change_set_id: event.change_set_id,
              work_item_id: event.work_item_id,
              agent_id: event.agent_id,
              base_snapshots: event.base_snapshots,
              lease_set_id: nil,
              status: "authorized"
            )
          when Events::AttemptStartedV1
            self.class.new(
              attempt_id:,
              change_set_id:,
              work_item_id:,
              agent_id:,
              base_snapshots:,
              lease_set_id:,
              status: "active"
            )
          when Events::WriteSetReservedV1
            self.class.new(
              attempt_id:,
              change_set_id:,
              work_item_id:,
              agent_id:,
              base_snapshots:,
              lease_set_id: event.lease_set_id,
              status:
            )
          else
            self
          end
        end
      end
    end
  end
end
