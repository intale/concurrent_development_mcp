# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ChangeSets
      class Activate
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, occurred_at:)
          denial = denied(state:, command:)
          return denial if denial

          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.change_set(command.change_set_id),
                  event: Events::ChangeSetActivatedV1.new(
                    change_set_id: command.change_set_id,
                    work_item_count: state.work_item_ids.length,
                    dependency_count: state.dependencies.length,
                    activated_at: occurred_at
                  )
                )
              ]
            )
          )
        end

        private

        def denied(state:, command:)
          return failure(:change_set_not_found, "ChangeSet does not exist", command) if state.absent?

          if state.status == "active"
            return failure(:change_set_already_active, "ChangeSet is already active", command)
          end

          if state.acceptance_criteria.empty?
            return failure(:change_set_has_no_criteria, "ChangeSet has no acceptance criteria", command)
          end

          if state.work_item_ids.empty?
            return failure(:change_set_has_no_work_items, "ChangeSet has no WorkItems", command)
          end

          missing_endpoint = state.dependencies.find { !endpoints_are_members?(state, _1) }
          if missing_endpoint
            return failure(
              :dependency_endpoint_missing,
              "Dependency endpoint is not a ChangeSet member",
              command,
              dependency_id: missing_endpoint.dependency_id
            )
          end

          return failure(:dependency_cycle, "ChangeSet dependency graph contains a cycle", command) if cycle?(state)

          nil
        end

        def endpoints_are_members?(state, dependency)
          state.work_item_ids.include?(dependency.producer_work_item_id) &&
            state.work_item_ids.include?(dependency.consumer_work_item_id)
        end

        def cycle?(state)
          work_item_ids = state.work_item_ids.uniq
          adjacency = work_item_ids.to_h { [ _1, [] ] }
          incoming = work_item_ids.to_h { [ _1, 0 ] }

          state.dependencies.each do |dependency|
            adjacency.fetch(dependency.producer_work_item_id) << dependency.consumer_work_item_id
            incoming[dependency.consumer_work_item_id] += 1
          end

          pending = incoming.filter_map { |work_item_id, count| work_item_id if count.zero? }
          visited = 0
          cursor = 0

          while cursor < pending.length
            work_item_id = pending.fetch(cursor)
            cursor += 1
            visited += 1

            adjacency.fetch(work_item_id).each do |consumer_id|
              incoming[consumer_id] -= 1
              pending << consumer_id if incoming.fetch(consumer_id).zero?
            end
          end

          visited != work_item_ids.length
        end

        def failure(code, message, command, details = {})
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: { change_set_id: command.change_set_id }.merge(details)
            )
          )
        end
      end
    end
  end
end
