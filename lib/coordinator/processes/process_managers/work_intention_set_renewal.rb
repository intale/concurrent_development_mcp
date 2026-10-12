# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class WorkIntentionSetRenewal
      def initialize(event_store:,
        loader: Coordinator::Write::WorkIntentionRenewals::Loader.new(event_store:),
        set_loader: Coordinator::Write::WorkIntentionSetLoader.new(event_store:),
        member_executor: Coordinator::Write::Operations::ExecuteRenewWorkIntention.new(event_store:),
        outcome_executor: Coordinator::Write::Operations::ExecuteRecordWorkIntentionRenewalOutcome.new(event_store:),
        command_transition: Coordinator::Write::Operations::ApplyCommandTransition.new(event_store:),
        command_loader: Coordinator::Write::CommandLifecycle::Loader.new(event_store:),
        task_outcome: Coordinator::Write::Operations::RecordCoordinationTaskOutcome.new(
          transition: Coordinator::Write::Operations::ApplyCoordinationTaskTransition.new(event_store:)),
        stream_factory: Coordinator::Write::StreamFactory.new,
        source_contract: Contracts::WorkIntentionRenewalSourceEvent.new)
        @event_store, @loader, @set_loader = event_store, loader, set_loader
        @member_executor, @outcome_executor = member_executor, outcome_executor
        @command_transition, @command_loader, @task_outcome = command_transition, command_loader, task_outcome
        @stream_factory, @source_contract = stream_factory, source_contract
      end

      def call(event)
        validation = @source_contract.call(event:)
        raise InvalidSourceEvent, validation.errors.to_h.inspect if validation.failure?
        snapshot = @loader.call(event.stream.stream_id)
        raise InvalidSourceEvent, "Renewal request does not match its stream" unless snapshot.events.first&.id == event.id
        set = @set_loader.call(snapshot.state.request.intention_set_id)
        actor = Coordinator::Write::Commands::Actor.new(kind: event.metadata.fetch("actor_kind"), id: event.metadata.fetch("actor_id"))
        snapshot.state.pending.each do |assignment|
          break if @loader.call(event.stream.stream_id).state.terminal
          source = snapshot.events.find { _1.type == "WorkIntentionRenewalAssigned" && _1.data.fetch("intention_id") == assignment.intention_id }
          command = Coordinator::Write::Commands::RenewWorkIntention.new(
            command_id: assignment.renew_command_id, actor:, renewal_id: assignment.renewal_id,
            intention_set_id: snapshot.state.request.intention_set_id, change_set_id: set.change_set_id,
            work_item_id: set.work_item_id, attempt_id: set.attempt_id, intention_id: assignment.intention_id,
            resource_id: assignment.resource_id, fencing_token: assignment.fencing_token, expires_at: snapshot.state.request.expires_at)
          result, failure = renew_member(command, caused_by: source)
          physical = result&.success? && result.value!
          outcome = Coordinator::Write::Commands::RecordWorkIntentionRenewalOutcome.new(
            command_id: assignment.outcome_command_id, actor:, renewal_id: assignment.renewal_id,
            intention_id: assignment.intention_id, renewal_event: physical ? reference(physical) : nil, failure:)
          @outcome_executor.call_command(outcome, caused_by: physical || source).value!
        end
        finalize(@loader.call(event.stream.stream_id), actor:)
        nil
      end

      private

      def renew_member(command, caused_by:)
        result = @member_executor.call_command(command, caused_by:)
        return [ result, nil ] if result.success?
        error = result.failure
        [ result, Coordinator::Write::WorkIntentionRenewals::MemberFailureV1.new(
          reason_code: error.code.to_s, reason: error.message[0, 2000],
          retryable: error.code == :concurrency_conflict, attempts: error.code == :concurrency_conflict ? 3 : 1) ]
      rescue StandardError => error
        Rails.error.report(error, handled: true)
        [ nil, Coordinator::Write::WorkIntentionRenewals::MemberFailureV1.new(
          reason_code: "execution_error", reason: error.message[0, 2000], retryable: false, attempts: 1) ]
      end

      def finalize(snapshot, actor:)
        return unless snapshot.state.terminal
        root_id = snapshot.state.request.renewal_id
        canonical = @command_loader.call(root_id)
        unless canonical.state.terminal?
          failed = snapshot.state.failed_member
          if failed
            outcome = Coordinator::Write::Commands::FailCommand.new(command_id: root_id,
              failure: Coordinator::Write::Tasks::ExecutionFailureV1.new(
                failed_step: "renew-member:#{failed.intention_id}", reason_code: failed.reason_code,
                reason: failed.reason, retryable: failed.retryable, effects_committed: snapshot.state.effects_committed?, attempts: failed.attempts))
            decider = Coordinator::Write::Domain::CommandLifecycles::Fail.new
          else
            outcome = Coordinator::Write::Commands::SucceedCommand.new(command_id: root_id)
            decider = Coordinator::Write::Domain::CommandLifecycles::Succeed.new
          end
          transition = @command_transition.call(command: outcome, decider:, actor:,
            tool_name: "work_intention_set_renew", caused_by: snapshot.events.last)
          canonical = @command_loader.call(root_id)
          transition.value! unless canonical.state.terminal?
        end
        submission = @event_store.read_global_marked(Coordinator::Write::GlobalMarkedEventReadCriteria.new(
          stream_context: "CoordinatorControl", stream_name: "CoordinationTask", event_types: [ "CoordinationTaskSubmitted" ],
          markers: [ "command:#{root_id}" ], maximum_count: 1, direction: :asc)).first
        raise Coordinator::Write::InvalidCommandHistory, "Renewal has no root Task instruction" unless submission
        @task_outcome.call(task_id: submission.data.fetch("task_id"),
          outcome: Coordinator::Write::Tasks::OutcomeV3::Completed.new, caused_by: canonical.persisted_events.last).value!
      end

      def reference(event)
        Coordinator::Write::EventReference.new(event_id: event.id, type: event.type,
          stream_context: event.stream.context, stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id, stream_revision: event.stream_revision)
      end
    end
  end
end
