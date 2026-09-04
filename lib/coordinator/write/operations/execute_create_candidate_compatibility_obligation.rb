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
        natural_key_builder: CandidateObligations::NaturalKeyBuilder.new,
        validity_builder: CandidateObligations::ValidityBuilder.new,
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
        @natural_key_builder = natural_key_builder
        @validity_builder = validity_builder
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
          event_ids: Array.new(4) { @id_generator.uuid_v7 }
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
        natural_key = @natural_key_builder.call(
          source:,
          target:,
          policy_partition_event: command.policy_partition_event,
          policy_head: command.policy_head,
          rule_version: command.rule_version
        )
        verify_command!(command, source:, target:, natural_key:)
        existing = @obligation_loader.find(natural_key)
        if existing
          return Success(result("replayed", existing.definition.obligation_id, existing.reference))
        end
        policy = @policy_loader.call(
          policy_partition_event: command.policy_partition_event,
          policy_head: command.policy_head,
          change_set_id: source.subject.change_set_id,
          observed_at: preparation.created_at
        )
        state = Domain::CandidateObligations::State.new(
          source:,
          target:,
          policy:,
          existing: nil
        )
        decision = @decider.call(
          state:,
          command:
        ).value!

        result_for(
          decision:,
          state:,
          command:,
          invocation:,
          preparation:,
          existing:,
          natural_key:
        )
      end

      def result_for(decision:, state:, command:, invocation:, preparation:, existing:, natural_key:)
        case decision.outcome
        when "created"
          events = persist_creation(
            decision:,
            state:,
            command:,
            invocation:,
            preparation:,
            natural_key:
          )
          Success(result(decision.outcome, command.obligation_id, event_reference(events.first)))
        when "replayed"
          Success(result(decision.outcome, command.obligation_id, existing.reference))
        else
          Success(result(decision.outcome, command.obligation_id, nil))
        end
      end

      def persist_creation(decision:, state:, command:, invocation:, preparation:, natural_key:)
        plan = decision.plan
        verify_event_plan!(
          plan,
          state:,
          command:
        )
        physical = plan.events.zip(preparation.event_ids).map do |event, event_id|
          @event_factory.build!(
            event:,
            event_id:,
            metadata: event_metadata(event, state:, command:),
            markers: event_markers(event, state:, command:, natural_key:),
            caused_by: invocation.caused_by
          )
        end
        @event_store.append(plan.writes.first.stream, physical)
      end

      def verify_invocation!(invocation)
        validation = @invocation_contract.call(invocation:)
        return if validation.success?

        raise ArgumentError,
              "Candidate compatibility obligation invocation violates its dry-rb contract: " \
              "#{validation.errors.to_h.inspect}"
      end

      def verify_command!(command, source:, target:, natural_key:)
        validation = @command_contract.call(
          command:,
          source:,
          target:,
          natural_key:
        )
        return if validation.success?

        raise ArgumentError,
              "Candidate compatibility obligation command violates its dry-rb contract: " \
              "#{validation.errors.to_h.inspect}"
      end

      def verify_event_plan!(plan, state:, command:)
        validation = @event_plan_contract.call(plan:, state:, command:)
        return if validation.success?

        raise ArgumentError,
              "Candidate compatibility obligation plan violates its dry-rb contract: " \
              "#{validation.errors.to_h.inspect}"
      end

      def event_metadata(event, state:, command:)
        common = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: command.rule_version
        }
        return EventMetadata.new(**common) unless event.is_a?(Events::VerificationObligationCreatedV2)

        reasons = CandidateObligations::Matcher.new.call(source: state.source, target: state.target)
        validity = @validity_builder.call(
          source: state.source,
          target: state.target,
          reasons:,
          policy: state.policy.evidence,
          rule_version: command.rule_version
        )
        Metadata::VerificationObligationV2.new(
          **common,
          policy: state.policy.evidence,
          rule_version: command.rule_version,
          validity_input_digest: validity.digest
        )
      end

      def event_markers(event, state:, command:, natural_key:)
        source = state.source.subject
        target = state.target.subject
        markers = [
          "verification-obligation:#{command.obligation_id}",
          "verification-obligation-kind:candidate_compatibility",
          "verification-obligation-status:open",
          "change-set:#{source.change_set_id}",
          "source-candidate:#{source.candidate_id}",
          "target-candidate:#{target.candidate_id}",
          "candidate:#{source.candidate_id}",
          "candidate:#{target.candidate_id}",
          "work-item:#{source.work_item_id}",
          "work-item:#{target.work_item_id}",
          "repository:#{source.repository_id}",
          "repository:#{target.repository_id}",
          "enforcement:#{state.policy.evidence.enforcement}",
          "decision:#{state.policy.evidence.head.decision_id}",
          "command:#{command.command_id}"
        ]
        markers << natural_key.marker if event.is_a?(Events::VerificationObligationCreatedV2)
        markers.freeze
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
