# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteCreateCandidateCompatibilityObligation
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        candidate_loader: CandidateObligations::CandidateEvidenceLoader.new(event_store:),
        policy_loader: CandidateObligations::ImpactPolicyLoader.new(event_store:),
        obligation_loader: CandidateObligations::ObligationLoader.new(event_store:),
        identity_builder: CandidateObligations::IdentityBuilder.new,
        decider: Domain::CandidateObligations::Create.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        invocation_contract: Contracts::CandidateCompatibilityObligationInvocation.new,
        command_contract: Contracts::CandidateCompatibilityObligationCommand.new,
        event_plan_contract: Contracts::CandidateCompatibilityObligationEventPlan.new
      )
        @event_store = event_store
        @candidate_loader = candidate_loader
        @policy_loader = policy_loader
        @obligation_loader = obligation_loader
        @identity_builder = identity_builder
        @decider = decider
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
        @invocation_contract = invocation_contract
        @command_contract = command_contract
        @event_plan_contract = event_plan_contract
      end

      def call(invocation)
        verify_invocation!(invocation)
        preparation = CandidateCompatibilityObligationPreparationV1.new(
          created_at: @clock.now,
          obligation_event_id: @id_generator.uuid_v7
        )

        @event_store.multiple do
          execute_attempt(invocation:, preparation:)
        end
      end

      private

      def execute_attempt(invocation:, preparation:)
        command = invocation.command
        source = @candidate_loader.call(command.source_registration)
        target = @candidate_loader.call(command.target_registration)
        identity = @identity_builder.call(
          source:,
          target:,
          policy_partition_event: command.policy_partition_event,
          policy_head: command.policy_head,
          rule_version: command.rule_version
        )
        verify_command!(command, source:, target:, identity:)
        policy = @policy_loader.call(
          policy_partition_event: command.policy_partition_event,
          policy_head: command.policy_head,
          change_set_id: source.subject.change_set_id,
          observed_at: preparation.created_at
        )
        existing = @obligation_loader.call(identity) if policy.status == "gating"
        state = Domain::CandidateObligations::State.new(
          source:,
          target:,
          policy:,
          existing: existing&.payload
        )
        decision = @decider.call(
          state:,
          command:,
          created_at: preparation.created_at
        ).value!

        result_for(
          decision:,
          state:,
          command:,
          invocation:,
          preparation:,
          existing:
        )
      end

      def result_for(decision:, state:, command:, invocation:, preparation:, existing:)
        case decision.outcome
        when "created"
          event = persist_creation(
            decision:,
            state:,
            command:,
            invocation:,
            preparation:
          )
          Success(result(decision.outcome, command.obligation_id, event_reference(event)))
        when "replayed"
          Success(result(decision.outcome, command.obligation_id, existing.reference))
        else
          Success(result(decision.outcome, command.obligation_id, nil))
        end
      end

      def persist_creation(decision:, state:, command:, invocation:, preparation:)
        plan = decision.plan
        verify_event_plan!(
          plan,
          state:,
          command:,
          created_at: preparation.created_at
        )
        physical = @event_factory.build!(
          event: decision.obligation,
          event_id: preparation.obligation_event_id,
          metadata: event_metadata(command),
          markers: event_markers(decision.obligation, command),
          caused_by: invocation.caused_by
        )
        @event_store.append(plan.writes.sole.stream, [ physical ]).sole
      end

      def verify_invocation!(invocation)
        validation = @invocation_contract.call(invocation:)
        return if validation.success?

        raise ArgumentError,
              "Candidate compatibility obligation invocation violates its dry-rb contract: " \
              "#{validation.errors.to_h.inspect}"
      end

      def verify_command!(command, source:, target:, identity:)
        validation = @command_contract.call(
          command:,
          source:,
          target:,
          expected_identity: identity
        )
        return if validation.success?

        raise ArgumentError,
              "Candidate compatibility obligation command violates its dry-rb contract: " \
              "#{validation.errors.to_h.inspect}"
      end

      def verify_event_plan!(plan, state:, command:, created_at:)
        validation = @event_plan_contract.call(plan:, state:, command:, created_at:)
        return if validation.success?

        raise ArgumentError,
              "Candidate compatibility obligation plan violates its dry-rb contract: " \
              "#{validation.errors.to_h.inspect}"
      end

      def event_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.rule_version
        )
      end

      def event_markers(obligation, command)
        source = obligation.source_candidate
        target = obligation.target_candidate
        [
          "verification-obligation:#{obligation.obligation_id}",
          "verification-obligation-kind:#{obligation.kind}",
          "verification-obligation-status:#{obligation.status}",
          "change-set:#{obligation.change_set_id}",
          "source-candidate:#{source.candidate_id}",
          "target-candidate:#{target.candidate_id}",
          "candidate:#{source.candidate_id}",
          "candidate:#{target.candidate_id}",
          "work-item:#{source.work_item_id}",
          "work-item:#{target.work_item_id}",
          "repository:#{source.repository_id}",
          "repository:#{target.repository_id}",
          "enforcement:#{obligation.enforcement}",
          "decision:#{obligation.policy.head.decision_id}",
          "command:#{command.command_id}"
        ].freeze
      end

      def result(outcome, obligation_id, event)
        CandidateObligations::ResultV1.new(outcome:, obligation_id:, event:)
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end
    end
  end
end
