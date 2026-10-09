# frozen_string_literal: true

module Coordinator::Read
  module Projections
    class CoordContextReducer
      def apply(state, event, occurred_at: nil)
        case event
        when Coordinator::Read::ChangeSetDefinitionViewV1 then apply_change_set_definition(state, event)
        when Coordinator::Read::WorkItemDefinitionViewV1 then apply_work_item_definition(state, event)
        when Coordinator::Write::Events::WorkItemDependencyDeclaredV2
          apply_dependency_declared(state, event, occurred_at:)
        when Coordinator::Write::Events::ChangeSetActivatedV2
          apply_change_set_activated(state, event, occurred_at:)
        when Coordinator::Write::Events::WorkItemMadeReadyV2
          apply_work_item_made_ready(state, event, occurred_at:)
        when Coordinator::Write::Events::WorkItemAcquiredV2
          apply_work_item_acquired(state, event, occurred_at:)
        when Coordinator::Read::AttemptDefinitionViewV1 then apply_attempt_definition(state, event)
        when Coordinator::Read::AttemptAbandonmentViewV1 then apply_attempt_abandonment(state, event)
        when Coordinator::Write::Events::WorkItemRequeuedV2
          apply_work_item_requeued(state, event, occurred_at:)
        when Coordinator::Write::Events::WriteSetReservedV2 then apply_write_set_reserved(state, event)
        when Coordinator::Write::Events::WriteSetExpandedV2 then apply_write_set_expanded(state, event)
        when Coordinator::Write::Events::WriteSetRenewedV2 then apply_write_set_renewed(state, event)
        when Coordinator::Write::Events::WriteSetReleasedV2 then apply_write_set_released(state, event)
        when Coordinator::Read::WorkIntentionSetViewV1 then apply_work_intention_set(state, event)
        when Coordinator::Read::CandidateSubmissionViewV2 then apply_candidate_submitted(state, event)
        when Coordinator::Write::Events::WorkItemCandidateSelectedV2
          apply_candidate_selected(state, event, occurred_at:)
        when Coordinator::Read::AttemptCompletionViewV1 then apply_attempt_completed(state, event)
        when Coordinator::Read::WorkItemCompletionViewV1 then apply_work_item_completed(state, event)
        when Coordinator::Write::Events::WorkItemDependencySatisfiedV2
          apply_dependency_satisfied(state, event, occurred_at:)
        when Coordinator::Write::Events::ChangeSetCompletedV2
          apply_change_set_completed(state, event, occurred_at:)
        else
          raise UnknownProjectionEvent, "coord_context/v1 does not handle #{event.class.name}"
        end
      end

      private

      def apply_change_set_definition(state, event)
        replace(
          state,
          change_set: CoordContextStateV1::ChangeSet.new(
            change_set_id: event.change_set_id,
            goal: event.goal,
            acceptance_criteria: event.acceptance_criteria,
            status: "planning",
            created_at: event.created_at,
            activated_at: nil,
            completed_at: nil
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

      def apply_work_item_definition(state, event)
        updated = apply_work_item_created(state, event)
        apply_work_item_added(updated, event)
      end

      def apply_work_item_added(state, event)
        require_change_set(state, event.change_set_id)
        ids = state.work_item_ids.include?(event.work_item_id) ? state.work_item_ids : state.work_item_ids + [ event.work_item_id ]
        replace(state, work_item_ids: ids)
      end

      def apply_dependency_declared(state, event, occurred_at: nil)
        require_change_set(state, event.change_set_id)
        dependency = CoordContextStateV1::Dependency.new(
          dependency_id: event.dependency_id,
          producer_work_item_id: event.producer_work_item_id,
          consumer_work_item_id: event.consumer_work_item_id,
          dependency_kind: event.dependency_kind,
          required_output: event.required_output,
          source_event: nil,
          declared_at: occurrence_time(event, occurred_at),
          satisfied_at: nil
        )

        replace(state, dependencies: upsert(state.dependencies, :dependency_id, dependency))
      end

      def apply_change_set_activated(state, event, occurred_at: nil)
        change_set = require_change_set(state, event.change_set_id)
        replace(
          state,
          change_set: CoordContextStateV1::ChangeSet.new(
            change_set.attributes.merge(
              status: "active",
              activated_at: occurrence_time(event, occurred_at)
            )
          )
        )
      end

      def apply_work_item_made_ready(state, event, occurred_at: nil)
        work_item = require_work_item(state, event.work_item_id, event.change_set_id)
        replace(
          state,
          work_items: upsert(
            state.work_items,
            :work_item_id,
            CoordContextStateV1::WorkItem.new(
              work_item.attributes.merge(
                status: "ready",
                made_ready_at: occurrence_time(event, occurred_at)
              )
            )
          )
        )
      end

      def apply_work_item_acquired(state, event, occurred_at: nil)
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
                acquired_at: occurrence_time(event, occurred_at)
              )
            )
          )
        )
      end

      def apply_work_item_requeued(state, event, occurred_at: nil)
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
                made_ready_at: occurrence_time(event, occurred_at),
                acquired_at: nil
              )
            )
          )
        )
      end

      def apply_attempt_definition(state, event)
        require_work_item(state, event.work_item_id, event.change_set_id)
        attempt = CoordContextStateV1::Attempt.new(
          attempt_id: event.attempt_id,
          change_set_id: event.change_set_id,
          work_item_id: event.work_item_id,
          agent_id: event.agent_id,
          base_snapshots: event.base_snapshots,
          status: "started",
          authorized_at: event.authorized_at,
          started_at: event.started_at,
          work_intention_set: nil,
          selected_candidate_id: nil,
          selected_candidate_event: nil,
          completed_at: nil,
          abandonment_reason: nil,
          abandoned_at: nil
        )

        replace_with_attempts(state, bounded_attempts(upsert(state.attempts, :attempt_id, attempt)))
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
                work_intention_set: nil,
                abandonment_reason: event.reason,
                abandoned_at: event.abandoned_at
              )
            )
          )
        )
      end

      def apply_attempt_abandonment(state, event)
        apply_attempt_abandoned(state, event)
      end

      def apply_write_set_reserved(state, event)
        attempt = require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)
        intention_set = CoordContextStateV1::WorkIntentionSet.new(
          intention_set_id: event.lease_set_id,
          repository_id: event.repository_id,
          policy_version: event.policy_version,
          intentions: event.resources.map do |resource|
            projected_work_intention(resource)
          end,
          declared_at: event.reserved_at,
          last_expanded_at: nil,
          last_renewed_at: nil,
          previous_expires_at: nil,
          expires_at: event.expires_at,
          withdrawn_at: nil
        )

        replace(
          state,
          attempts: upsert(
            state.attempts,
            :attempt_id,
            CoordContextStateV1::Attempt.new(attempt.attributes.merge(work_intention_set: intention_set))
          )
        )
      end

      def apply_write_set_expanded(state, event)
        attempt = require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)
        intention_set = attempt.work_intention_set
        raise ProjectionStateError, "Attempt #{event.attempt_id} has no projected work-intention set" unless intention_set
        unless intention_set.intention_set_id == event.lease_set_id &&
               intention_set.repository_id == event.repository_id &&
               intention_set.policy_version == event.policy_version &&
               intention_set.expires_at == event.expires_at
          raise ProjectionStateError, "Attempt #{event.attempt_id} write-set identity changed"
        end

        intentions = event.added_resources.reduce(intention_set.intentions) do |observed, reference|
          upsert_work_intention(observed, projected_work_intention(reference))
        end.sort_by { _1.resource_id.b }
        unless intentions.length == event.resource_count
          raise ProjectionStateError, "Attempt #{event.attempt_id} write-set count changed"
        end

        expanded = CoordContextStateV1::WorkIntentionSet.new(
          intention_set.attributes.merge(
            intentions:,
            last_expanded_at: event.expanded_at,
            expires_at: event.expires_at
          )
        )
        replace(
          state,
          attempts: upsert(
            state.attempts,
            :attempt_id,
            CoordContextStateV1::Attempt.new(attempt.attributes.merge(work_intention_set: expanded))
          )
        )
      end

      def apply_write_set_renewed(state, event)
        attempt = require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)
        intention_set = attempt.work_intention_set
        raise ProjectionStateError, "Attempt #{event.attempt_id} has no projected work-intention set" unless intention_set
        unless intention_set.intention_set_id == event.lease_set_id &&
               intention_set.repository_id == event.repository_id &&
               intention_set.policy_version == event.policy_version
          raise ProjectionStateError, "Attempt #{event.attempt_id} write-set identity changed"
        end
        unless legacy_intention_identities(intention_set.intentions) == event.resources.map(&:to_h) &&
               intention_set.intentions.length == event.resource_count
          raise ProjectionStateError, "Attempt #{event.attempt_id} write-set membership changed during renewal"
        end
        unless intention_set.expires_at == event.previous_expires_at && event.expires_at > event.previous_expires_at
          raise ProjectionStateError, "Attempt #{event.attempt_id} renewal deadline is not contiguous"
        end

        renewed = CoordContextStateV1::WorkIntentionSet.new(
          intention_set.attributes.merge(
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
            CoordContextStateV1::Attempt.new(attempt.attributes.merge(work_intention_set: renewed))
          )
        )
      end

      def apply_write_set_released(state, event)
        attempt = require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)
        intention_set = attempt.work_intention_set
        raise ProjectionStateError, "Attempt #{event.attempt_id} has no projected work-intention set" unless intention_set
        unless intention_set.intention_set_id == event.lease_set_id &&
               intention_set.repository_id == event.repository_id &&
               intention_set.policy_version == event.policy_version
          raise ProjectionStateError, "Attempt #{event.attempt_id} write-set identity changed"
        end
        unless legacy_intention_identities(intention_set.intentions) == event.resources.map(&:to_h) &&
               intention_set.intentions.length == event.resource_count
          raise ProjectionStateError, "Attempt #{event.attempt_id} write-set membership changed during release"
        end
        unless intention_set.expires_at == event.previous_expires_at && intention_set.withdrawn_at.nil?
          raise ProjectionStateError, "Attempt #{event.attempt_id} release is not contiguous"
        end

        withdrawn = CoordContextStateV1::WorkIntentionSet.new(
          intention_set.attributes.merge(withdrawn_at: event.released_at)
        )
        replace(
          state,
          attempts: upsert(
            state.attempts,
            :attempt_id,
            CoordContextStateV1::Attempt.new(attempt.attributes.merge(work_intention_set: withdrawn))
          )
        )
      end

      def apply_work_intention_set(state, event)
        attempt = require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)
        unless attempt.agent_id == event.agent_id
          raise ProjectionStateError, "Attempt #{event.attempt_id} work-intention attribution changed"
        end

        intention_set = CoordContextStateV1::WorkIntentionSet.new(
          intention_set_id: event.set_id,
          repository_id: event.repository_id,
          policy_version: event.policy_version,
          intentions: event.intentions.map { projected_work_intention(_1) },
          declared_at: event.declared_at,
          last_expanded_at: event.last_expanded_at,
          last_renewed_at: event.last_renewed_at,
          previous_expires_at: event.previous_expires_at,
          expires_at: event.expires_at,
          withdrawn_at: event.withdrawn_at
        )
        replace(
          state,
          attempts: upsert(
            state.attempts,
            :attempt_id,
            CoordContextStateV1::Attempt.new(attempt.attributes.merge(work_intention_set: intention_set))
          )
        )
      end

      def apply_candidate_submitted(state, event)
        require_attempt(state, event.attempt_id, event.change_set_id, event.work_item_id)
        checkpoint = CoordContextStateV1::CandidateCheckpoint.new(
          candidate_id: event.candidate_id,
          candidate_event: event_reference(event.submitted_event),
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
          attached_at: event.submitted_event.created_at.utc.iso8601(6)
        )

        replace(
          state,
          candidate_checkpoints: retained_candidate_checkpoints(
            upsert(state.candidate_checkpoints, :attempt_id, checkpoint),
            attempts: state.attempts
          )
        )
      end

      def event_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def apply_candidate_selected(state, event, occurred_at: nil)
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
                selected_at: occurrence_time(event, occurred_at)
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
                work_intention_set: nil,
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

      def apply_dependency_satisfied(state, event, occurred_at: nil)
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
                source_event: event.source,
                satisfied_at: occurrence_time(event, occurred_at)
              )
            )
          )
        )
      end

      def apply_change_set_completed(state, event, occurred_at: nil)
        change_set = require_change_set(state, event.change_set_id)
        replace(
          state,
          change_set: CoordContextStateV1::ChangeSet.new(
            change_set.attributes.merge(
              status: "completed",
              completed_at: occurrence_time(event, occurred_at)
            )
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

      def replace_with_attempts(state, attempts)
        replace(
          state,
          attempts:,
          candidate_checkpoints: retained_candidate_checkpoints(
            state.candidate_checkpoints,
            attempts:
          )
        )
      end

      def retained_candidate_checkpoints(checkpoints, attempts:)
        retained_attempt_ids = attempts.to_set(&:attempt_id)
        checkpoints.select { retained_attempt_ids.include?(_1.attempt_id) }
      end

      def projected_work_intention(reference)
        attributes = reference.to_h
        if attributes.key?(:lease_id)
          attributes = attributes.merge(
            intention_id: attributes.delete(:lease_id),
            mode: "exclusive",
            purpose: "Legacy Resource reservation",
            context: nil
          )
        end
        CoordContextStateV1::WorkIntention.new(attributes)
      end

      def legacy_intention_identities(intentions)
        intentions.map do |intention|
          intention.to_h.slice(
            :intention_id,
            :resource_id,
            :resource_kind,
            :resource_path,
            :base_blob_oid,
            :fencing_token
          ).transform_keys { _1 == :intention_id ? :lease_id : _1 }
        end
      end

      def upsert_work_intention(collection, replacement)
        existing_index = collection.index { _1.resource_id == replacement.resource_id }
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

      def occurrence_time(event, observed)
        return observed if observed

        raise ProjectionStateError, "#{event.class.name} requires its persisted Event.created_at"
      end
    end
  end
end
