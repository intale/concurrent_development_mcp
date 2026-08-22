# frozen_string_literal: true

module Coordinator::Read
  module Projections
    class CoordContextReducer
      def apply(state, event)
        case event
        when Coordinator::Write::Events::ChangeSetCreatedV1 then apply_change_set_created(state, event)
        when Coordinator::Write::Events::ChangeSetAcceptanceCriteriaDefinedV1 then apply_acceptance_criteria(state, event)
        when Coordinator::Write::Events::WorkItemCreatedV1 then apply_work_item_created(state, event)
        when Coordinator::Write::Events::WorkItemAddedToChangeSetV1 then apply_work_item_added(state, event)
        when Coordinator::Write::Events::WorkItemDependencyDeclaredV1 then apply_dependency_declared(state, event)
        when Coordinator::Write::Events::ChangeSetActivatedV1 then apply_change_set_activated(state, event)
        when Coordinator::Write::Events::WorkItemMadeReadyV1 then apply_work_item_made_ready(state, event)
        when Coordinator::Write::Events::WorkItemAcquiredV1 then apply_work_item_acquired(state, event)
        when Coordinator::Write::Events::AttemptAuthorizedV1 then apply_attempt_authorized(state, event)
        when Coordinator::Write::Events::AttemptStartedV1 then apply_attempt_started(state, event)
        when Coordinator::Write::Events::WriteSetReservedV1 then apply_write_set_reserved(state, event)
        when Coordinator::Write::Events::WriteSetExpandedV1 then apply_write_set_expanded(state, event)
        else
          raise UnknownProjectionEvent, "coord_context/v1 does not handle #{event.class.name}"
        end
      end

      private

      def apply_change_set_created(state, event)
        replace(
          state,
          change_set: CoordContextStateV1::ChangeSet.new(
            change_set_id: event.change_set_id,
            goal: event.goal,
            acceptance_criteria: [],
            status: "planning",
            created_at: event.created_at,
            activated_at: nil
          )
        )
      end

      def apply_acceptance_criteria(state, event)
        change_set = require_change_set(state, event.change_set_id)
        replace(
          state,
          change_set: CoordContextStateV1::ChangeSet.new(
            change_set.attributes.merge(acceptance_criteria: event.acceptance_criteria)
          )
        )
      end

      def apply_work_item_created(state, event)
        work_item = CoordContextStateV1::WorkItem.new(
          work_item_id: event.work_item_id,
          change_set_id: event.change_set_id,
          repository_id: event.repository_id,
          goal: event.goal,
          acceptance_criteria: event.acceptance_criteria,
          competitive_mode: event.competitive_mode,
          status: "planned",
          active_attempt_id: nil,
          active_agent_id: nil,
          created_at: event.created_at,
          made_ready_at: nil,
          acquired_at: nil
        )

        replace(state, work_items: upsert(state.work_items, :work_item_id, work_item))
      end

      def apply_work_item_added(state, event)
        require_change_set(state, event.change_set_id)
        ids = state.work_item_ids.include?(event.work_item_id) ? state.work_item_ids : state.work_item_ids + [ event.work_item_id ]
        replace(state, work_item_ids: ids)
      end

      def apply_dependency_declared(state, event)
        require_change_set(state, event.change_set_id)
        dependency = CoordContextStateV1::Dependency.new(
          dependency_id: event.dependency_id,
          producer_work_item_id: event.producer_work_item_id,
          consumer_work_item_id: event.consumer_work_item_id,
          dependency_kind: event.dependency_kind,
          required_output: event.required_output,
          declared_at: event.declared_at
        )

        replace(state, dependencies: upsert(state.dependencies, :dependency_id, dependency))
      end

      def apply_change_set_activated(state, event)
        change_set = require_change_set(state, event.change_set_id)
        replace(
          state,
          change_set: CoordContextStateV1::ChangeSet.new(
            change_set.attributes.merge(status: "active", activated_at: event.activated_at)
          )
        )
      end

      def apply_work_item_made_ready(state, event)
        work_item = require_work_item(state, event.work_item_id, event.change_set_id)
        replace(
          state,
          work_items: upsert(
            state.work_items,
            :work_item_id,
            CoordContextStateV1::WorkItem.new(
              work_item.attributes.merge(status: "ready", made_ready_at: event.made_ready_at)
            )
          )
        )
      end

      def apply_work_item_acquired(state, event)
        work_item = require_work_item(state, event.work_item_id, event.change_set_id)
        replace(
          state,
          work_items: upsert(
            state.work_items,
            :work_item_id,
            CoordContextStateV1::WorkItem.new(
              work_item.attributes.merge(
                status: "acquired",
                active_attempt_id: event.attempt_id,
                active_agent_id: event.agent_id,
                acquired_at: event.acquired_at
              )
            )
          )
        )
      end

      def apply_attempt_authorized(state, event)
        require_work_item(state, event.work_item_id, event.change_set_id)
        attempt = CoordContextStateV1::Attempt.new(
          attempt_id: event.attempt_id,
          change_set_id: event.change_set_id,
          work_item_id: event.work_item_id,
          agent_id: event.agent_id,
          base_snapshots: event.base_snapshots,
          status: "authorized",
          authorized_at: event.authorized_at,
          started_at: nil,
          write_set: nil
        )

        replace(state, attempts: upsert(state.attempts, :attempt_id, attempt))
      end

      def apply_attempt_started(state, event)
        attempt = require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)

        replace(
          state,
          attempts: upsert(
            state.attempts,
            :attempt_id,
            CoordContextStateV1::Attempt.new(
              attempt.attributes.merge(status: "started", started_at: event.started_at)
            )
          )
        )
      end

      def apply_write_set_reserved(state, event)
        attempt = require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)
        write_set = CoordContextStateV1::WriteSet.new(
          lease_set_id: event.lease_set_id,
          repository_id: event.repository_id,
          policy_version: event.policy_version,
          resources: event.resources.map do |resource|
            CoordContextStateV1::WriteSetResource.new(resource.to_h)
          end,
          reserved_at: event.reserved_at,
          last_expanded_at: nil,
          expires_at: event.expires_at
        )

        replace(
          state,
          attempts: upsert(
            state.attempts,
            :attempt_id,
            CoordContextStateV1::Attempt.new(attempt.attributes.merge(write_set:))
          )
        )
      end

      def apply_write_set_expanded(state, event)
        attempt = require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)
        write_set = attempt.write_set
        raise ProjectionStateError, "Attempt #{event.attempt_id} has no projected write set" unless write_set
        unless write_set.lease_set_id == event.lease_set_id &&
               write_set.repository_id == event.repository_id &&
               write_set.policy_version == event.policy_version &&
               write_set.expires_at == event.expires_at
          raise ProjectionStateError, "Attempt #{event.attempt_id} write-set identity changed"
        end

        resources = event.added_resources.reduce(write_set.resources) do |observed, reference|
          upsert(
            observed,
            :resource_key_hash,
            CoordContextStateV1::WriteSetResource.new(reference.to_h)
          )
        end.sort_by { _1.resource_key_hash.b }
        unless resources.length == event.resource_count
          raise ProjectionStateError, "Attempt #{event.attempt_id} write-set count changed"
        end

        expanded = CoordContextStateV1::WriteSet.new(
          write_set.attributes.merge(
            resources:,
            last_expanded_at: event.expanded_at,
            expires_at: event.expires_at
          )
        )
        replace(
          state,
          attempts: upsert(
            state.attempts,
            :attempt_id,
            CoordContextStateV1::Attempt.new(attempt.attributes.merge(write_set: expanded))
          )
        )
      end

      def require_change_set(state, change_set_id)
        change_set = state.change_set
        raise ProjectionStateError, "ChangeSet #{change_set_id} is not projected" unless change_set
        raise ProjectionStateError, "ChangeSet scope changed" unless change_set.change_set_id == change_set_id

        change_set
      end

      def require_work_item(state, work_item_id, change_set_id)
        work_item = state.work_items.find { _1.work_item_id == work_item_id }
        raise ProjectionStateError, "WorkItem #{work_item_id} is not projected" unless work_item
        raise ProjectionStateError, "WorkItem #{work_item_id} scope changed" unless work_item.change_set_id == change_set_id

        work_item
      end

      def require_attempt(state, attempt_id, change_set_id, work_item_id)
        attempt = state.attempts.find { _1.attempt_id == attempt_id }
        raise ProjectionStateError, "Attempt #{attempt_id} is not projected" unless attempt
        unless attempt.change_set_id == change_set_id && attempt.work_item_id == work_item_id
          raise ProjectionStateError, "Attempt #{attempt_id} scope changed"
        end

        attempt
      end

      def replace(state, **changes)
        CoordContextStateV1.new(state.attributes.merge(changes))
      end

      def upsert(collection, identity_method, replacement)
        existing_index = collection.index { _1.public_send(identity_method) == replacement.public_send(identity_method) }
        return collection + [ replacement ] unless existing_index

        collection.each_with_index.map { |value, index| index == existing_index ? replacement : value }
      end
    end
  end
end
