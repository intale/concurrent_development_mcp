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
        when Coordinator::Write::Events::AttemptAbandonedV2 then apply_attempt_abandoned(state, event)
        when Coordinator::Write::Events::WorkItemRequeuedV1 then apply_work_item_requeued(state, event)
        when Coordinator::Write::Events::WriteSetReservedV2 then apply_write_set_reserved(state, event)
        when Coordinator::Write::Events::WriteSetExpandedV2 then apply_write_set_expanded(state, event)
        when Coordinator::Write::Events::WriteSetRenewedV2 then apply_write_set_renewed(state, event)
        when Coordinator::Write::Events::WriteSetReleasedV2 then apply_write_set_released(state, event)
        when Coordinator::Write::Events::CandidateAttachedToAttemptV1 then apply_candidate_attached(state, event)
        when Coordinator::Write::Events::WorkItemCandidateSelectedV1 then apply_candidate_selected(state, event)
        when Coordinator::Write::Events::AttemptCompletedV1 then apply_attempt_completed(state, event)
        when Coordinator::Write::Events::WorkItemCompletedV1 then apply_work_item_completed(state, event)
        when Coordinator::Write::Events::WorkItemDependencySatisfiedV1 then apply_dependency_satisfied(state, event)
        when Coordinator::Write::Events::ChangeSetCompletedV1 then apply_change_set_completed(state, event)
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
            activated_at: nil,
            completed_at: nil
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
          selected_candidate_id: nil,
          selected_candidate_event: nil,
          produced_outputs: [],
          created_at: event.created_at,
          made_ready_at: nil,
          acquired_at: nil,
          selected_at: nil,
          completed_at: nil
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
          source_event: nil,
          declared_at: event.declared_at,
          satisfied_at: nil
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

      def apply_work_item_requeued(state, event)
        work_item = require_work_item(state, event.work_item_id, event.change_set_id)
        return state if work_item.status == "completed"
        return state if work_item.active_attempt_id && work_item.active_attempt_id != event.attempt_id
        if work_item.active_agent_id && work_item.active_agent_id != event.agent_id
          raise ProjectionStateError, "WorkItem #{event.work_item_id} active attribution changed"
        end

        replace(
          state,
          work_items: upsert(
            state.work_items,
            :work_item_id,
            CoordContextStateV1::WorkItem.new(
              work_item.attributes.merge(
                status: "ready",
                active_attempt_id: nil,
                active_agent_id: nil,
                made_ready_at: event.requeued_at,
                acquired_at: nil
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
          write_set: nil,
          selected_candidate_id: nil,
          selected_candidate_event: nil,
          completed_at: nil,
          abandonment_reason: nil,
          abandoned_at: nil
        )

        replace(state, attempts: bounded_attempts(upsert(state.attempts, :attempt_id, attempt)))
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

      def apply_attempt_abandoned(state, event)
        attempt = state.attempts.find { _1.attempt_id == event.attempt_id }
        return state unless attempt
        unless attempt.change_set_id == event.change_set_id && attempt.work_item_id == event.work_item_id
          raise ProjectionStateError, "Attempt #{event.attempt_id} scope changed"
        end
        raise ProjectionStateError, "Attempt #{event.attempt_id} attribution changed" unless attempt.agent_id == event.agent_id
        return state if attempt.status == "abandoned" && attempt.abandoned_at == event.abandoned_at
        raise ProjectionStateError, "Completed Attempt #{event.attempt_id} cannot be abandoned" if attempt.status == "completed"

        replace(
          state,
          attempts: upsert(
            state.attempts,
            :attempt_id,
            CoordContextStateV1::Attempt.new(
              attempt.attributes.merge(
                status: "abandoned",
                write_set: nil,
                abandonment_reason: event.reason,
                abandoned_at: event.abandoned_at
              )
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
            projected_write_set_resource(resource)
          end,
          reserved_at: event.reserved_at,
          last_expanded_at: nil,
          last_renewed_at: nil,
          previous_expires_at: nil,
          expires_at: event.expires_at,
          released_at: nil
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
          upsert_write_set_resource(observed, projected_write_set_resource(reference))
        end.sort_by { write_set_resource_identity(_1).b }
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

      def apply_write_set_renewed(state, event)
        attempt = require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)
        write_set = attempt.write_set
        raise ProjectionStateError, "Attempt #{event.attempt_id} has no projected write set" unless write_set
        unless write_set.lease_set_id == event.lease_set_id &&
               write_set.repository_id == event.repository_id &&
               write_set.policy_version == event.policy_version
          raise ProjectionStateError, "Attempt #{event.attempt_id} write-set identity changed"
        end
        unless write_set.resources.map(&:to_h) == event.resources.map(&:to_h) &&
               write_set.resources.length == event.resource_count
          raise ProjectionStateError, "Attempt #{event.attempt_id} write-set membership changed during renewal"
        end
        unless write_set.expires_at == event.previous_expires_at && event.expires_at > event.previous_expires_at
          raise ProjectionStateError, "Attempt #{event.attempt_id} renewal deadline is not contiguous"
        end

        renewed = CoordContextStateV1::WriteSet.new(
          write_set.attributes.merge(
            last_renewed_at: event.renewed_at,
            previous_expires_at: event.previous_expires_at,
            expires_at: event.expires_at
          )
        )
        replace(
          state,
          attempts: upsert(
            state.attempts,
            :attempt_id,
            CoordContextStateV1::Attempt.new(attempt.attributes.merge(write_set: renewed))
          )
        )
      end

      def apply_write_set_released(state, event)
        attempt = require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)
        write_set = attempt.write_set
        raise ProjectionStateError, "Attempt #{event.attempt_id} has no projected write set" unless write_set
        unless write_set.lease_set_id == event.lease_set_id &&
               write_set.repository_id == event.repository_id &&
               write_set.policy_version == event.policy_version
          raise ProjectionStateError, "Attempt #{event.attempt_id} write-set identity changed"
        end
        unless write_set.resources.map(&:to_h) == event.resources.map(&:to_h) &&
               write_set.resources.length == event.resource_count
          raise ProjectionStateError, "Attempt #{event.attempt_id} write-set membership changed during release"
        end
        unless write_set.expires_at == event.previous_expires_at && write_set.released_at.nil?
          raise ProjectionStateError, "Attempt #{event.attempt_id} release is not contiguous"
        end

        released = CoordContextStateV1::WriteSet.new(
          write_set.attributes.merge(released_at: event.released_at)
        )
        replace(
          state,
          attempts: upsert(
            state.attempts,
            :attempt_id,
            CoordContextStateV1::Attempt.new(attempt.attributes.merge(write_set: released))
          )
        )
      end

      def apply_candidate_attached(state, event)
        require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)
        checkpoint = CoordContextStateV1::CandidateCheckpoint.new(
          candidate_id: event.candidate_id,
          candidate_event: event.candidate_event,
          change_set_id: event.change_set_id,
          work_item_id: event.work_item_id,
          attempt_id: event.attempt_id,
          repository_id: event.repository_id,
          target_branch: event.target_branch,
          object_format: event.object_format,
          base_commit_oid: event.base_commit_oid,
          head_commit_oid: event.head_commit_oid,
          checkpoint_kind: event.checkpoint_kind,
          manifest_digest: event.manifest_digest,
          build_context_digest: event.build_context_digest,
          attached_at: event.attached_at
        )

        replace(
          state,
          candidate_checkpoints: upsert(
            state.candidate_checkpoints,
            :attempt_id,
            checkpoint
          )
        )
      end

      def apply_candidate_selected(state, event)
        work_item = require_work_item(state, event.work_item_id, event.change_set_id)
        replace(
          state,
          work_items: upsert(
            state.work_items,
            :work_item_id,
            CoordContextStateV1::WorkItem.new(
              work_item.attributes.merge(
                selected_candidate_id: event.candidate_id,
                selected_candidate_event: event.candidate_event,
                selected_at: event.selected_at
              )
            )
          )
        )
      end

      def apply_attempt_completed(state, event)
        attempt = require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)
        replace(
          state,
          attempts: upsert(
            state.attempts,
            :attempt_id,
            CoordContextStateV1::Attempt.new(
              attempt.attributes.merge(
                status: "completed",
                write_set: nil,
                selected_candidate_id: event.candidate_id,
                selected_candidate_event: event.candidate_event,
                completed_at: event.completed_at
              )
            )
          )
        )
      end

      def apply_work_item_completed(state, event)
        work_item = require_work_item(state, event.work_item_id, event.change_set_id)
        replace(
          state,
          work_items: upsert(
            state.work_items,
            :work_item_id,
            CoordContextStateV1::WorkItem.new(
              work_item.attributes.merge(
                status: "completed",
                selected_candidate_id: event.candidate_id,
                selected_candidate_event: event.candidate_event,
                produced_outputs: event.produced_outputs,
                completed_at: event.completed_at
              )
            )
          )
        )
      end

      def apply_dependency_satisfied(state, event)
        require_change_set(state, event.change_set_id)
        dependency = state.dependencies.find { _1.dependency_id == event.dependency_id }
        raise ProjectionStateError, "Dependency #{event.dependency_id} is not projected" unless dependency
        unless dependency.producer_work_item_id == event.producer_work_item_id &&
               dependency.consumer_work_item_id == event.consumer_work_item_id &&
               dependency.dependency_kind == event.dependency_kind &&
               dependency.required_output == event.required_output
          raise ProjectionStateError, "Dependency #{event.dependency_id} definition changed"
        end

        replace(
          state,
          dependencies: upsert(
            state.dependencies,
            :dependency_id,
            CoordContextStateV1::Dependency.new(
              dependency.attributes.merge(
                source_event: event.source_event,
                satisfied_at: event.satisfied_at
              )
            )
          )
        )
      end

      def apply_change_set_completed(state, event)
        change_set = require_change_set(state, event.change_set_id)
        replace(
          state,
          change_set: CoordContextStateV1::ChangeSet.new(
            change_set.attributes.merge(status: "completed", completed_at: event.completed_at)
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

      def projected_write_set_resource(reference)
        CoordContextStateV1::WriteSetResource.new(reference.to_h)
      end

      def write_set_resource_identity(resource)
        resource.resource_id
      end

      def upsert_write_set_resource(collection, replacement)
        identity = write_set_resource_identity(replacement)
        existing_index = collection.index { write_set_resource_identity(_1) == identity }
        return collection + [ replacement ] unless existing_index

        collection.each_with_index.map { |value, index| index == existing_index ? replacement : value }
      end

      def upsert(collection, identity_method, replacement)
        existing_index = collection.index { _1.public_send(identity_method) == replacement.public_send(identity_method) }
        return collection + [ replacement ] unless existing_index

        collection.each_with_index.map { |value, index| index == existing_index ? replacement : value }
      end

      def bounded_attempts(attempts)
        terminal, nonterminal = attempts.partition { terminal_attempt?(_1) }
        terminal_capacity = CoordContextStateV1::RECENT_ATTEMPT_LIMIT - nonterminal.length
        if terminal_capacity.negative?
          raise ProjectionStateError, "nonterminal Attempt count exceeds the embedded projection bound"
        end

        retained_terminal = terminal.sort_by { [ _1.authorized_at, _1.attempt_id.b ] }
                                    .last(terminal_capacity)
        (nonterminal + retained_terminal)
          .sort_by { [ _1.authorized_at, _1.attempt_id.b ] }
          .reverse
      end

      def terminal_attempt?(attempt)
        %w[abandoned completed].include?(attempt.status)
      end
    end
  end
end
