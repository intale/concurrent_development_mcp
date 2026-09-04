# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationOutcomes
    class Executor
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        state_loader: VerificationObligations::OutcomeStateLoader.new(event_store:),
        outcome_digest_builder: CompatibilityAssessments::OutcomeDigestBuilder.new,
        event_factory: EventFactory.new,
        id_generator: IdGenerator.new
      )
        @event_store = event_store
        @state_loader = state_loader
        @outcome_digest_builder = outcome_digest_builder
        @event_factory = event_factory
        @id_generator = id_generator
      end

      def call(command:, decider:, caused_by: nil)
        state = @state_loader.call(command.obligation_id)
        decision = decider.call(state:, command:)
        return decision if decision.failure?

        plan = decision.value!
        physical = build_events(plan.events, state:, command:, caused_by:)
        persisted = @event_store.append(
          plan.writes.first.stream,
          physical,
          expected_revision: state.latest_revision
        )
        Success(persisted)
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(
          OutcomeError.new(
            code: :stale_stream,
            message: "Verification obligation changed concurrently; the request may succeed if retried",
            details: { obligation_id: command.obligation_id }
          )
        )
      end

      private

      def build_events(events, state:, command:, caused_by:)
        parent = caused_by
        correlation_id = parent&.correlation_id || @id_generator.uuid_v7
        events.map do |event|
          physical = @event_factory.build!(
            event:,
            event_id: @id_generator.uuid_v7,
            metadata: metadata(event, state:, command:),
            markers: markers(event, state.definition, command),
            caused_by: parent,
            correlation_id:
          )
          parent = physical
          physical
        end
      end

      def metadata(event, state:, command:)
        common = {
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "verification-obligation-outcome/v2"
        }
        return EventMetadata.new(common) if event.is_a?(Events::VerificationObligationEvidenceSelectedV1)

        Metadata::VerificationOutcomeV2.new(
          common.merge(
            outcome_digest: outcome_digest(event, state, command),
            policy: state.definition.policy
          )
        )
      end

      def outcome_digest(event, state, command)
        if event.is_a?(Events::VerificationObligationSatisfiedV2)
          selected = command.selected_evidence_ids.map do |evidence_id|
            state.observation(evidence_id).decision_reference
          end
          @outcome_digest_builder.satisfied(obligation: state.definition, selected_evidence: selected)
        else
          triggering = state.observation(command.triggering_evidence_id).decision_reference
          @outcome_digest_builder.failed(obligation: state.definition, triggering_evidence: triggering)
        end
      end

      def markers(event, definition, command)
        markers = scope_markers(definition) + [ "command:#{command.command_id}" ]
        case event
        when Events::VerificationObligationEvidenceSelectedV1
          markers + [ "verification-evidence:#{event.evidence_id}" ]
        when Events::VerificationObligationSatisfiedV2
          markers + [ "verification-obligation-status:satisfied" ]
        when Events::VerificationObligationFailedV2
          markers + [ "verification-obligation-status:failed" ]
        end
      end

      def scope_markers(obligation)
        source = obligation.source_candidate
        target = obligation.target_candidate
        [
          "verification-obligation:#{obligation.obligation_id}",
          "verification-obligation-kind:#{obligation.kind}",
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
          "decision:#{obligation.policy.head.decision_id}"
        ]
      end
    end
  end
end
