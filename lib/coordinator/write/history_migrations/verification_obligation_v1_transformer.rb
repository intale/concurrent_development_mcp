# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class VerificationObligationV1Transformer
      include Dry::Monads[:result]

      TERMINAL_TARGETS = {
        "satisfied" => [ "VerificationObligationSatisfied", "satisfy-verification-obligation" ],
        "failed" => [ "VerificationObligationFailed", "fail-verification-obligation" ],
        "waived" => [ "VerificationObligationWaived", "waive-verification-obligation" ],
        "invalidated" => [ "VerificationObligationInvalidated", "invalidate-verification-obligation" ]
      }.freeze

      def initialize(context_resolver:)
        @context_resolver = context_resolver
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        if source_payload.is_a?(Events::VerificationObligationCreatedV1)
          context = @context_resolver.from_creation(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_creation: source_payload
          )
          return context if context.failure?

          return Success(creation_facts(context.value!, source_event))
        end

        context = @context_resolver.from_stream(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        )
        return context if context.failure?

        transformed = transform_lifecycle(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_payload,
          context: context.value!
        )
        transformed.failure? ? transformed : Success(Array(transformed.value!))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def creation_facts(context, source_event)
        source = context.source_creation
        common = context.markers(status: "open")
        created = fact(
          context:,
          event: Events::VerificationObligationCreatedV2.new(
            obligation_id: context.obligation_id,
            kind: source.kind,
            enforcement: source.enforcement,
            reasons: source.reasons.map(&:kind),
            required_evidence: source.required_evidence
          ),
          markers: common + [ context.natural_key_marker ],
          step_name: "create-verification-obligation",
          metadata_extension: MigrationMetadataExtensionV1.new(
            attributed_actor: actor_from(source_event),
            policy_version: source.rule_version,
            policy: context.policy,
            rule_version: source.rule_version,
            validity_input_digest: source.validity_input_digest
          )
        )
        relation_metadata = actor_metadata(source_event, policy_version: source.rule_version)
        [
          created,
          fact(
            context:,
            event: Events::VerificationObligationAddedToChangeSetV1.new(
              obligation_id: context.obligation_id,
              change_set_id: context.change_set_id
            ),
            markers: common,
            step_name: "add-verification-obligation-to-change-set",
            metadata_extension: relation_metadata
          ),
          fact(
            context:,
            event: Events::VerificationObligationSourceCandidateAssignedV1.new(
              obligation_id: context.obligation_id,
              candidate_id: context.source_candidate.target_subject.candidate_id
            ),
            markers: common,
            step_name: "assign-verification-obligation-source-candidate",
            metadata_extension: relation_metadata
          ),
          fact(
            context:,
            event: Events::VerificationObligationTargetCandidateAssignedV1.new(
              obligation_id: context.obligation_id,
              candidate_id: context.target_candidate.target_subject.candidate_id
            ),
            markers: common,
            step_name: "assign-verification-obligation-target-candidate",
            metadata_extension: relation_metadata
          )
        ].freeze
      end

      def transform_lifecycle(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        context:
      )
        case source
        when Events::VerificationObligationClaimedV1
          transform_claim(source_event:, source:, context:)
        when Events::VerificationEvidenceSubmittedV1
          transform_evidence(
            migration_id:,
            source_upper_position:,
            source_event:,
            source:,
            context:
          )
        when Events::VerificationObligationSatisfiedV1
          transform_satisfied(
            migration_id:,
            source_upper_position:,
            source_event:,
            source:,
            context:
          )
        when Events::VerificationObligationFailedV1
          transform_failed(
            migration_id:,
            source_upper_position:,
            source_event:,
            source:,
            context:
          )
        when Events::VerificationObligationWaivedV1
          transform_waived(
            migration_id:,
            source_upper_position:,
            source_event:,
            source:,
            context:
          )
        when Events::VerificationObligationInvalidatedV1
          transform_invalidated(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source:,
            context:
          )
        else
          Failure(inconsistent(source_event, "unsupported verification-obligation source contract"))
        end
      end

      def transform_claim(source_event:, source:, context:)
        valid = validate_common(source_event, source, context)
        return valid if valid.failure?

        Success(
          fact(
            context:,
            event: Events::VerificationObligationClaimedV2.new(
              obligation_id: context.obligation_id,
              claim_id: source.claim_id,
              claimant_id: source.claimant_id,
              fencing_token: source.fencing_token,
              expires_at: source.expires_at
            ),
            markers: context.scope_markers + [
              "claim:#{source.claim_id}",
              "claimant:#{source.claimant_id}"
            ],
            step_name: "claim-verification-obligation",
            metadata_extension: actor_metadata(
              source_event,
              policy_version: "verification-obligation-claim/v1"
            )
          )
        )
      end

      def transform_evidence(migration_id:, source_upper_position:, source_event:, source:, context:)
        valid = validate_common(source_event, source, context)
        return valid if valid.failure?
        unless source.source_candidate == context.source_creation.source_candidate &&
            source.target_candidate == context.source_creation.target_candidate &&
            source.policy == context.source_creation.policy &&
            source.obligation_validity_input_digest == context.source_creation.validity_input_digest
          return Failure(inconsistent(source_event, "submitted evidence disagrees with the obligation definition"))
        end

        claim = resolve_claim(
          migration_id:,
          source_upper_position:,
          source_event:,
          source:,
          context:
        )
        return claim if claim.failure?

        Success(
          fact(
            context:,
            event: Events::VerificationEvidenceSubmittedV2.new(
              evidence_id: source.evidence_id,
              obligation_id: context.obligation_id,
              evidence_kind: source.evidence_kind,
              assessment: source.assessment,
              claim: claim.value!
            ),
            markers: context.scope_markers + [
              "verification-evidence:#{source.evidence_id}",
              "verification-evidence-kind:#{source.evidence_kind}",
              "verification-evidence-conclusion:#{source.assessment.conclusion}",
              "claim:#{source.claim.claim_id}",
              "claimant:#{source.claim.claimant_id}"
            ],
            step_name: "submit-verification-evidence",
            metadata_extension: MigrationMetadataExtensionV1.new(
              attributed_actor: actor_from(source_event),
              policy_version: "compatibility-assessment/v2",
              assessment_input_digest: source.assessment_input_digest,
              obligation_validity_input_digest: source.obligation_validity_input_digest,
              policy: context.policy
            )
          )
        )
      end

      def transform_satisfied(migration_id:, source_upper_position:, source_event:, source:, context:)
        valid = validate_outcome(source_event, source, context)
        return valid if valid.failure?

        selections = transform_selections(
          migration_id:,
          source_upper_position:,
          source_event:,
          context:,
          evidence: source.selected_evidence
        )
        return selections if selections.failure?

        terminal = fact(
          context:,
          event: Events::VerificationObligationSatisfiedV2.new(obligation_id: context.obligation_id),
          markers: context.markers(status: "satisfied"),
          step_name: "satisfy-verification-obligation",
          metadata_extension: outcome_metadata(source_event, context, source.outcome_digest)
        )
        Success(selections.value! + [ terminal ])
      end

      def transform_failed(migration_id:, source_upper_position:, source_event:, source:, context:)
        valid = validate_outcome(source_event, source, context)
        return valid if valid.failure?

        selections = transform_selections(
          migration_id:,
          source_upper_position:,
          source_event:,
          context:,
          evidence: [ source.triggering_evidence ]
        )
        return selections if selections.failure?

        terminal = fact(
          context:,
          event: Events::VerificationObligationFailedV2.new(
            obligation_id: context.obligation_id,
            reason: nil
          ),
          markers: context.markers(status: "failed"),
          step_name: "fail-verification-obligation",
          metadata_extension: outcome_metadata(source_event, context, source.outcome_digest)
        )
        Success(selections.value! + [ terminal ])
      end

      def transform_waived(migration_id:, source_upper_position:, source_event:, source:, context:)
        valid = validate_outcome(source_event, source, context)
        return valid if valid.failure?

        previous = validate_previous_terminal(
          migration_id:,
          source_upper_position:,
          source_event:,
          context:,
          status: source.previous_status,
          reference: source.previous_terminal_event
        )
        return previous if previous.failure?

        Success(
          fact(
            context:,
            event: Events::VerificationObligationWaivedV2.new(
              obligation_id: context.obligation_id,
              reason: source.reason
            ),
            markers: context.markers(status: "waived"),
            step_name: "waive-verification-obligation",
            metadata_extension: MigrationMetadataExtensionV1.new(
              attributed_actor: actor_from(source_event),
              policy_version: "verification-obligation-waiver/v2",
              policy: context.policy,
              waiver_input_digest: source.waiver_input_digest
            )
          )
        )
      end

      def transform_invalidated(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        context:
      )
        valid = validate_common(source_event, source, context)
        return valid if valid.failure?
        unless source.invalidated_policy == context.source_creation.policy
          return Failure(inconsistent(source_event, "invalidation policy disagrees with the obligation definition"))
        end

        previous = validate_previous_terminal(
          migration_id:,
          source_upper_position:,
          source_event:,
          context:,
          status: source.previous_status,
          reference: source.previous_terminal_event
        )
        return previous if previous.failure?

        partition = @context_resolver.partition_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.superseding_partition_event
        )
        return partition if partition.failure?

        Success(
          fact(
            context:,
            event: Events::VerificationObligationInvalidatedV2.new(
              obligation_id: context.obligation_id,
              superseding_partition_event: partition.value!.first,
              reason: source.reason
            ),
            markers: context.markers(status: "invalidated"),
            step_name: "invalidate-verification-obligation",
            metadata_extension: MigrationMetadataExtensionV1.new(
              attributed_actor: actor_from(source_event),
              policy_version: source.rule_version,
              invalidated_policy: context.policy,
              invalidation_digest: source.invalidation_digest,
              rule_version: source.rule_version
            )
          )
        )
      end

      def transform_selections(
        migration_id:,
        source_upper_position:,
        source_event:,
        context:,
        evidence:
      )
        evidence_ids = evidence.map(&:evidence_id)
        unless evidence_ids.uniq.length == evidence_ids.length
          return Failure(inconsistent(source_event, "selected evidence contains duplicate identities"))
        end

        facts = []
        evidence.each_with_index do |decision, index|
          valid = validate_evidence_decision(
            migration_id:,
            source_upper_position:,
            source_event:,
            context:,
            decision:
          )
          return valid if valid.failure?

          facts << fact(
            context:,
            event: Events::VerificationObligationEvidenceSelectedV1.new(
              obligation_id: context.obligation_id,
              evidence_id: decision.evidence_id
            ),
            markers: context.scope_markers + [ "verification-evidence:#{decision.evidence_id}" ],
            step_name: "select-verification-obligation-evidence-#{index + 1}",
            metadata_extension: actor_metadata(
              source_event,
              policy_version: "verification-obligation-outcome/v2"
            )
          )
        end
        Success(facts.freeze)
      end

      def validate_evidence_decision(
        migration_id:,
        source_upper_position:,
        source_event:,
        context:,
        decision:
      )
        loaded = @context_resolver.load_reference(
          source_event:,
          source_upper_position:,
          source_reference: decision.event
        )
        return loaded if loaded.failure?

        payload = loaded.value!.last
        valid = payload.is_a?(Events::VerificationEvidenceSubmittedV1) &&
                payload.obligation_id == context.source_creation.obligation_id &&
                payload.obligation_event == context.source_creation_reference &&
                [
                  payload.evidence_kind,
                  payload.evidence_id,
                  payload.assessment.conclusion,
                  payload.assessment.result_digest,
                  payload.assessment_input_digest
                ] == [
                  decision.evidence_kind,
                  decision.evidence_id,
                  decision.conclusion,
                  decision.result_digest,
                  decision.assessment_input_digest
                ]
        return Failure(inconsistent(source_event, "selected evidence disagrees with its source fact")) unless valid

        @context_resolver.target_reference(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: decision.event,
          target_stream: context.target_stream,
          target_event_type: "VerificationEvidenceSubmitted",
          target_step_name: "submit-verification-evidence"
        )
      end

      def resolve_claim(migration_id:, source_upper_position:, source_event:, source:, context:)
        loaded = @context_resolver.load_reference(
          source_event:,
          source_upper_position:,
          source_reference: source.claim.claim_event
        )
        return loaded if loaded.failure?

        payload = loaded.value!.last
        valid = payload.is_a?(Events::VerificationObligationClaimedV1) &&
                payload.obligation_id == context.source_creation.obligation_id &&
                payload.obligation_event == context.source_creation_reference &&
                [ payload.claim_id, payload.claimant_id, payload.fencing_token ] ==
                  [ source.claim.claim_id, source.claim.claimant_id, source.claim.fencing_token ]
        return Failure(inconsistent(source_event, "claim binding disagrees with its source fact")) unless valid

        target = @context_resolver.target_reference(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: source.claim.claim_event,
          target_stream: context.target_stream,
          target_event_type: "VerificationObligationClaimed",
          target_step_name: "claim-verification-obligation"
        )
        return target if target.failure?

        Success(
          CompatibilityAssessments::ClaimEvidenceV1.new(
            source.claim.to_h.merge(claim_event: target.value!)
          )
        )
      end

      def validate_previous_terminal(
        migration_id:,
        source_upper_position:,
        source_event:,
        context:,
        status:,
        reference:
      )
        return Success() if status == "open" && reference.nil?
        return Failure(inconsistent(source_event, "previous terminal evidence is incomplete")) unless reference

        target = TERMINAL_TARGETS[status]
        return Failure(inconsistent(source_event, "previous terminal status is unsupported")) unless target

        loaded = @context_resolver.load_reference(
          source_event:,
          source_upper_position:,
          source_reference: reference
        )
        return loaded if loaded.failure?

        payload = loaded.value!.last
        unless payload.respond_to?(:obligation_id) &&
            payload.obligation_id == context.source_creation.obligation_id
          return Failure(inconsistent(source_event, "previous terminal fact identifies another obligation"))
        end

        @context_resolver.target_reference(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: reference,
          target_stream: context.target_stream,
          target_event_type: target.fetch(0),
          target_step_name: target.fetch(1)
        )
      end

      def validate_common(source_event, source, context)
        valid = source.obligation_id == context.source_creation.obligation_id &&
                source.obligation_event == context.source_creation_reference
        return Success() if valid

        Failure(inconsistent(source_event, "event identifies another obligation or creation fact"))
      end

      def validate_outcome(source_event, source, context)
        common = validate_common(source_event, source, context)
        return common if common.failure?
        return Success() if source.policy == context.source_creation.policy

        Failure(inconsistent(source_event, "outcome policy disagrees with the obligation definition"))
      end

      def outcome_metadata(source_event, context, outcome_digest)
        MigrationMetadataExtensionV1.new(
          attributed_actor: actor_from(source_event),
          policy_version: "verification-obligation-outcome/v2",
          outcome_digest:,
          policy: context.policy
        )
      end

      def fact(context:, event:, markers:, step_name:, metadata_extension:)
        TransformedFactV1.new(
          target_stream: context.target_stream,
          event:,
          markers: markers.uniq.freeze,
          step_name:,
          metadata_extension:
        )
      end

      def actor_metadata(source_event, policy_version: nil)
        MigrationMetadataExtensionV1.new(
          attributed_actor: actor_from(source_event),
          policy_version:
        )
      end

      def actor_from(source_event)
        Commands::Actor.new(
          kind: source_event.metadata.fetch("actor_kind"),
          id: source_event.metadata.fetch("actor_id")
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Verification obligation source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
