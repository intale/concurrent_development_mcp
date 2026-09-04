# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ChangeSets
      class DeclareWorkItemDependency
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, occurred_at:)
          denial = denied(state:, command:)
          return denial if denial

          Success(build_plan(command:, occurred_at:))
        end

        private

        def denied(state:, command:)
          return failure(:change_set_not_found, "ChangeSet does not exist", command) if state.absent?
          return failure(:change_set_not_draft, "ChangeSet no longer accepts planning", command) unless state.status == "draft"
          return failure(:work_item_not_member, "Dependency endpoint is not a ChangeSet member", command) unless endpoints_are_members?(state, command)

          if command.producer_work_item_id == command.consumer_work_item_id
            return failure(:dependency_self_reference, "A WorkItem cannot depend on itself", command)
          end

          if state.dependencies.any? { _1.dependency_id == command.dependency_id }
            return failure(:dependency_id_reused, "Dependency ID is already used", command)
          end

          if state.dependencies.length >= 500
            return failure(:dependency_limit_reached, "ChangeSet dependency limit reached", command)
          end

          unless required_output_matches?(command)
            return failure(:required_output_mismatch, "Dependency kind and required output do not match", command)
          end

          return failure(:dependency_cycle, "Dependency would create a cycle", command) if creates_cycle?(state, command)

          nil
        end

        def endpoints_are_members?(state, command)
          state.work_item_ids.include?(command.producer_work_item_id) &&
            state.work_item_ids.include?(command.consumer_work_item_id)
        end

        def required_output_matches?(command)
          expected_kind = {
            "requires_artifact" => "artifact",
            "requires_contract" => "contract",
            "requires_composite_verification" => "verification_run"
          }[command.dependency_kind]

          return command.required_output.nil? unless expected_kind

          command.required_output&.kind == expected_kind
        end

        def creates_cycle?(state, command)
          adjacency = state.dependencies.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |dependency, graph|
            graph[dependency.producer_work_item_id] << dependency.consumer_work_item_id
          end
          adjacency[command.producer_work_item_id] << command.consumer_work_item_id

          reachable?(adjacency, from: command.consumer_work_item_id, target: command.producer_work_item_id)
        end

        def reachable?(adjacency, from:, target:)
          pending = [ from ]
          visited = {}

          until pending.empty?
            work_item_id = pending.pop
            return true if work_item_id == target
            next if visited[work_item_id]

            visited[work_item_id] = true
            pending.concat(adjacency[work_item_id])
          end

          false
        end

        def failure(code, message, command)
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: {
                change_set_id: command.change_set_id,
                dependency_id: command.dependency_id,
                producer_work_item_id: command.producer_work_item_id,
                consumer_work_item_id: command.consumer_work_item_id
              }
            )
          )
        end

        def build_plan(command:, occurred_at:)
          EventPlan.new(
            writes: [
              EventWrite.new(
                stream: @stream_factory.work_item(command.consumer_work_item_id),
                event: Events::WorkItemDependencyDeclaredV2.new(
                  change_set_id: command.change_set_id,
                  dependency_id: command.dependency_id,
                  producer_work_item_id: command.producer_work_item_id,
                  consumer_work_item_id: command.consumer_work_item_id,
                  dependency_kind: command.dependency_kind,
                  required_output: command.required_output
                )
              )
            ]
          )
        end
      end
    end
  end
end
