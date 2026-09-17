# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class ReleaseSetV1Transformer
      include Dry::Monads[:result]

      RELEASE_REFERENCE_TARGETS = {
        "RepositoryIntegrationRecorded" => [ "RepositoryIntegrationRecorded", "record-repository-integration" ],
        "ReleaseSetVerificationRecorded" => [ "ReleaseSetVerificationRecorded", "record-release-set-verification" ],
        "ReleaseSetActivated" => [ "ReleaseSetActivated", "activate-release-set" ],
        "ReleaseSetCompensationRequested" => [ "ReleaseSetCompensationRequested", "request-release-set-compensation" ]
      }.freeze

      def initialize(
        event_store:,
        context_resolver:,
        digest_builder: ReleaseSetLegacyDigestBuilder.new,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @context_resolver = context_resolver
        @digest_builder = digest_builder
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        context = resolve_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_payload:
        )
        return context if context.failure?

        state = source_state(source_event:, source_upper_position:)
        return state if state.failure?

        transformed = transform(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_payload,
          context: context.value!,
          state: state.value!
        )
        transformed.failure? ? transformed : Success(Array(transformed.value!).freeze)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def resolve_context(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_payload:
      )
        common = { migration_id:, source_config_name:, source_upper_position:, source_event: }
        if source_payload.is_a?(Events::ReleaseSetPreparedV1)
          @context_resolver.from_preparation(**common, source_preparation: source_payload)
        else
          @context_resolver.from_stream(**common)
        end
      end

      def transform(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        context:,
        state:
      )
        common = {
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          context:,
          state:
        }
        case source
        when Events::ReleaseSetPreparedV1 then transform_preparation(source_event:, source:, context:, state:)
        when Events::RepositoryIntegrationRecordedV1 then transform_integration(**common, source:)
        when Events::ReleaseSetVerificationRecordedV1 then transform_verification(**common, source:)
        when Events::ReleaseSetActivatedV1 then transform_activation(**common, source:)
        when Events::ReleaseSetCompensationRequestedV1 then transform_compensation(**common, source:)
        when Events::ReleaseSetCompletedV1 then transform_completion(**common, source:)
        else Failure(inconsistent(source_event, "unsupported ReleaseSet source contract"))
        end
      end

      def transform_preparation(source_event:, source:, context:, state:)
        unless state.preparation&.payload == source && valid_release_digest?(source)
          return Failure(inconsistent(source_event, "ReleaseSet preparation digest or history is inconsistent"))
        end

        actor = actor_metadata(source_event)
        facts = [
          fact(
            context:,
            event: Events::ReleaseSetCreatedV1.new(
              release_set_id: context.release_set_id,
              change_set_id: context.change_set_id
            ),
            markers: context.markers,
            step_name: "create-release-set",
            metadata_extension: actor
          )
        ]
        context.members.each_with_index do |member, index|
          facts << fact(
            context:,
            event: member.target_member,
            markers: context.markers + member.target_member.ordered_candidate_ids.map { "candidate:#{_1}" },
            step_name: "add-release-set-member-#{index + 1}",
            metadata_extension: actor
          )
        end
        facts << fact(
          context:,
          event: Events::ReleaseSetPreparedV2.new(release_set_id: context.release_set_id),
          markers: context.markers + [ "release-set-policy:#{source.policy_version}" ],
          step_name: "prepare-release-set",
          metadata_extension: actor_metadata(
            source_event,
            policy_version: source.policy_version,
            release_digest: source.release_digest
          )
        )
        Success(facts)
      end

      def transform_integration(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        context:,
        state:
      )
        member = context.member(source.repository_id)
        unless member && valid_integration?(source, context:, state:, member:)
          return Failure(inconsistent(source_event, "repository integration disagrees with ReleaseSet history"))
        end

        failure = transform_failure(source.failure)
        markers = [
          "release-set:#{context.release_set_id}",
          "repository:#{member.target_repository_id}",
          "release-integration-attempt:#{source.attempt_id}",
          "release-integration-outcome:#{source.outcome}"
        ]
        facts = [
          fact(
            context:,
            event: Events::RepositoryIntegrationRecordedV2.new(
              release_set_id: context.release_set_id,
              change_set_id: context.change_set_id,
              repository_id: member.target_repository_id,
              member_position: source.member_position,
              attempt_id: source.attempt_id,
              attempt_number: source.attempt_number,
              outcome: source.outcome,
              failure:
            ),
            markers:,
            step_name: "record-repository-integration",
            metadata_extension: actor_metadata(
              source_event,
              policy_version: source.policy_version,
              integration_digest: source.integration_digest,
              observation_digest: source.observation_digest,
              release_digest: source.release_digest
            )
          )
        ]
        return Success(facts) unless source.merge_observation_event

        observation = resolve_observation(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source:,
          member:
        )
        return observation if observation.failure?

        target_observation = observation.value!
        facts << fact(
          context:,
          event: Events::RepositoryIntegrationMergeLinkedV1.new(
            release_set_id: context.release_set_id,
            repository_id: member.target_repository_id,
            merge_observation: target_observation
          ),
          markers: markers + [ "merge-snapshot:#{target_observation.stream_id}" ],
          step_name: "link-repository-integration-merge",
          metadata_extension: actor_metadata(source_event)
        )
        Success(facts)
      end

      def transform_verification(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        context:,
        state:
      )
        unless valid_verification?(source, context:, state:)
          return Failure(inconsistent(source_event, "ReleaseSet verification disagrees with integration history"))
        end

        target_integrations = transform_release_references(
          migration_id:,
          source_upper_position:,
          source_event:,
          references: source.integration_events,
          context:,
          expected_type: "RepositoryIntegrationRecorded"
        )
        return target_integrations if target_integrations.failure?

        markers = [
          "release-set:#{context.release_set_id}",
          "release-verification-attempt:#{source.attempt_number}",
          "release-verification-outcome:#{source.evidence.outcome}"
        ]
        facts = [
          fact(
            context:,
            event: Events::ReleaseSetVerificationRecordedV2.new(
              release_set_id: context.release_set_id,
              change_set_id: context.change_set_id,
              attempt_number: source.attempt_number,
              evidence: ReleaseSets::VerificationEvidenceV2.new(source.evidence.to_h)
            ),
            markers:,
            step_name: "record-release-set-verification",
            metadata_extension: actor_metadata(
              source_event,
              policy_version: source.policy_version,
              release_digest: source.release_digest,
              verification_digest: source.verification_digest
            )
          )
        ]
        target_integrations.value!.each_with_index do |reference, index|
          facts << fact(
            context:,
            event: Events::ReleaseSetIntegrationLinkedV1.new(
              release_set_id: context.release_set_id,
              integration_event: reference
            ),
            markers: markers + [ "repository-integration-event:#{reference.event_id}" ],
            step_name: "link-release-set-integration-#{index + 1}",
            metadata_extension: actor_metadata(source_event)
          )
        end
        Success(facts)
      end

      def transform_activation(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        context:,
        state:
      )
        unless valid_activation?(source, context:, state:)
          return Failure(inconsistent(source_event, "ReleaseSet activation disagrees with verification history"))
        end

        verification = transform_release_reference(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: source.verification_event,
          context:,
          expected_type: "ReleaseSetVerificationRecorded"
        )
        return verification if verification.failure?

        Success(
          fact(
            context:,
            event: Events::ReleaseSetActivatedV2.new(
              release_set_id: context.release_set_id,
              change_set_id: context.change_set_id,
              activation_point: ReleaseSets::ActivationPointV2.new(
                kind: source.activation_point.kind,
                environment: source.activation_point.environment,
                external_reference: source.activation_point.external_reference,
                state_digest: source.activation_point.state_digest,
                producer: source.activation_point.producer,
                run_id: source.activation_point.run_id
              )
            ),
            markers: [
              "release-set:#{context.release_set_id}",
              "release-activation-kind:#{source.activation_point.kind}",
              "release-verification-event:#{verification.value!.event_id}"
            ],
            step_name: "activate-release-set",
            metadata_extension: actor_metadata(
              source_event,
              policy_version: source.policy_version,
              activation_digest: source.activation_digest,
              release_digest: source.release_digest,
              verification_digest: source.verification_digest
            )
          )
        )
      end

      def transform_compensation(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        context:,
        state:
      )
        unless valid_compensation?(source, context:, state:)
          return Failure(inconsistent(source_event, "ReleaseSet compensation request disagrees with lifecycle history"))
        end

        trigger = transform_release_reference(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: source.trigger_event,
          context:,
          expected_type: source.trigger_event.type
        )
        return trigger if trigger.failure?

        integrations = transform_release_references(
          migration_id:,
          source_upper_position:,
          source_event:,
          references: source.successful_integrations,
          context:,
          expected_type: "RepositoryIntegrationRecorded"
        )
        return integrations if integrations.failure?

        markers = [
          "release-set:#{context.release_set_id}",
          "release-compensation-trigger:#{trigger.value!.event_id}"
        ]
        facts = [
          fact(
            context:,
            event: Events::ReleaseSetCompensationRequestedV2.new(
              release_set_id: context.release_set_id,
              change_set_id: context.change_set_id,
              reason: source.reason,
              trigger_kind: source.trigger_kind
            ),
            markers:,
            step_name: "request-release-set-compensation",
            metadata_extension: actor_metadata(
              source_event,
              policy_version: source.rule_version,
              release_digest: source.release_digest,
              rule_version: source.rule_version
            )
          )
        ]
        integrations.value!.each_with_index do |reference, index|
          facts << fact(
            context:,
            event: Events::ReleaseSetSuccessfulIntegrationLinkedV1.new(
              release_set_id: context.release_set_id,
              integration_event: reference
            ),
            markers: markers + [ "repository-integration-event:#{reference.event_id}" ],
            step_name: "link-release-set-successful-integration-#{index + 1}",
            metadata_extension: actor_metadata(source_event)
          )
        end
        Success(facts)
      end

      def transform_completion(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        context:,
        state:
      )
        unless valid_completion?(source, context:, state:)
          return Failure(inconsistent(source_event, "ReleaseSet completion disagrees with lifecycle history"))
        end

        source_link = transform_release_reference(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: source.source_event,
          context:,
          expected_type: source.source_event.type
        )
        return source_link if source_link.failure?

        evidence = transform_compensation_evidence(
          migration_id:,
          source_upper_position:,
          source_event:,
          source:,
          context:
        )
        return evidence if evidence.failure?

        markers = [
          "release-set:#{context.release_set_id}",
          "release-completion:#{source.outcome}",
          "release-completion-source:#{source_link.value!.event_id}"
        ]
        facts = evidence.value!
        facts << fact(
          context:,
          event: Events::ReleaseSetOutcomeRecordedV1.new(
            release_set_id: context.release_set_id,
            outcome: source.outcome
          ),
          markers:,
          step_name: "record-release-set-outcome",
          metadata_extension: actor_metadata(
            source_event,
            policy_version: source.rule_version,
            completion_digest: source.completion_digest,
            release_digest: source.release_digest,
            rule_version: source.rule_version
          )
        )
        facts << fact(
          context:,
          event: Events::ReleaseSetCompletedV2.new(release_set_id: context.release_set_id),
          markers:,
          step_name: "complete-release-set",
          metadata_extension: actor_metadata(source_event, policy_version: source.rule_version)
        )
        Success(facts)
      end

      def transform_compensation_evidence(
        migration_id:,
        source_upper_position:,
        source_event:,
        source:,
        context:
      )
        facts = []
        source.compensation_evidence.each_with_index do |evidence, index|
          member = context.member(evidence.repository_id)
          unless member
            return Failure(inconsistent(source_event, "compensation evidence names a non-member repository"))
          end

          integration = transform_release_reference(
            migration_id:,
            source_upper_position:,
            source_event:,
            source_reference: evidence.integration_event,
            context:,
            expected_type: "RepositoryIntegrationRecorded"
          )
          return integration if integration.failure?

          facts << fact(
            context:,
            event: Events::RepositoryCompensationRecordedV1.new(
              release_set_id: context.release_set_id,
              repository_id: member.target_repository_id,
              integration_event: integration.value!,
              action: evidence.action,
              external_reference: evidence.external_reference
            ),
            markers: [
              "release-set:#{context.release_set_id}",
              "release-completion:compensated",
              "repository:#{member.target_repository_id}",
              "repository-integration-event:#{integration.value!.event_id}"
            ],
            step_name: "record-repository-compensation-#{index + 1}",
            metadata_extension: actor_metadata(
              source_event,
              policy_version: source.rule_version,
              result_digest: evidence.result_digest,
              producer: evidence.producer,
              run_id: evidence.run_id
            )
          )
        end
        Success(facts)
      end

      def resolve_observation(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        member:
      )
        loaded = @context_resolver.load_reference(
          source_event:,
          source_upper_position:,
          source_reference: source.merge_observation_event
        )
        return loaded if loaded.failure?

        observation = loaded.value!.last
        source_member = member.source_member
        valid = observation.is_a?(Events::MergeObservedV1) &&
                observation.merge_snapshot_id == source_member.merge_snapshot_id &&
                observation.authorization_event == source_member.authorization_event &&
                observation.authorization_decision_digest == source_member.authorization_decision_digest &&
                observation.snapshot_binding == source_member.snapshot_binding &&
                observation.repository_id == source_member.repository_id &&
                observation.target_branch == source_member.target_branch &&
                observation.object_format == source_member.object_format &&
                observation.target_before_commit_oid == source_member.target_base_commit_oid &&
                observation.target_after_commit_oid == source_member.merge_commit_oid &&
                observation.observation_digest == source.observation_digest
        unless valid
          return Failure(inconsistent(source_event, "integration MergeObserved evidence is inconsistent"))
        end

        @context_resolver.target_merge_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.merge_observation_event
        )
      end

      def transform_release_references(
        migration_id:,
        source_upper_position:,
        source_event:,
        references:,
        context:,
        expected_type:
      )
        transformed = []
        references.each do |reference|
          result = transform_release_reference(
            migration_id:,
            source_upper_position:,
            source_event:,
            source_reference: reference,
            context:,
            expected_type:
          )
          return result if result.failure?

          transformed << result.value!
        end
        Success(transformed.freeze)
      end

      def transform_release_reference(
        migration_id:,
        source_upper_position:,
        source_event:,
        source_reference:,
        context:,
        expected_type:
      )
        target = RELEASE_REFERENCE_TARGETS[source_reference.type]
        unless target && source_reference.type == expected_type
          return Failure(inconsistent(source_event, "unsupported ReleaseSet reference #{source_reference.type}"))
        end

        loaded = @context_resolver.load_reference(
          source_event:,
          source_upper_position:,
          source_reference:
        )
        return loaded if loaded.failure?
        referenced_event = loaded.value!.first
        unless referenced_event.stream == source_event.stream && referenced_event.stream_revision < source_event.stream_revision
          return Failure(inconsistent(source_event, "ReleaseSet reference does not identify an earlier owning-stream fact"))
        end

        @context_resolver.target_release_reference(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference:,
          context:,
          target_event_type: target.fetch(0),
          target_step_name: target.fetch(1)
        )
      end

      def valid_release_digest?(source)
        @digest_builder.call(
          :release,
          release_set_id: source.release_set_id,
          change_set_id: source.change_set_id,
          ordered_members: source.ordered_members,
          policy_version: source.policy_version
        ) == source.release_digest
      end

      def valid_integration?(source, context:, state:, member:)
        preparation = context.source_preparation
        prior = state.integrations.length > 1 ? state.integrations.first(state.integrations.length - 1) : []
        prior_for_member = prior.select { _1.payload.repository_id == source.repository_id }
        prior_members_integrated = context.members
          .take(member.source_member.position - 1)
          .all? do |candidate|
            prior.reverse.find do |integration|
              integration.payload.repository_id == candidate.source_repository_id
            end&.payload&.outcome == "integrated"
          end
        source.release_set_id == preparation.release_set_id &&
          source.change_set_id == preparation.change_set_id &&
          source.release_digest == preparation.release_digest &&
          source.member_position == member.source_member.position &&
          state.integrations.last&.payload == source &&
          state.integrations_for(source.repository_id).last&.payload == source &&
          state.integrations_for(source.repository_id).length == source.attempt_number &&
          prior.none? { _1.payload.attempt_id == source.attempt_id } &&
          prior_for_member.none? { _1.payload.outcome == "integrated" } &&
          prior_members_integrated &&
          state.activation.nil? && state.compensation_request.nil? && state.completion.nil? &&
          integration_evidence_shape_valid?(source) &&
          @digest_builder.call(
            :integration,
            release_set_id: source.release_set_id,
            release_digest: source.release_digest,
            repository_id: source.repository_id,
            member_position: source.member_position,
            attempt_id: source.attempt_id,
            attempt_number: source.attempt_number,
            outcome: source.outcome,
            merge_observation_event: source.merge_observation_event,
            observation_digest: source.observation_digest,
            failure: source.failure,
            policy_version: source.policy_version
          ) == source.integration_digest
      end

      def integration_evidence_shape_valid?(source)
        if source.outcome == "integrated"
          source.merge_observation_event && source.observation_digest && source.failure.nil?
        else
          source.merge_observation_event.nil? && source.observation_digest.nil? && !source.failure.nil?
        end
      end

      def valid_verification?(source, context:, state:)
        preparation = context.source_preparation
        prior = state.verifications.length > 1 ? state.verifications.first(state.verifications.length - 1) : []
        source.release_set_id == preparation.release_set_id &&
          source.change_set_id == preparation.change_set_id &&
          source.release_digest == preparation.release_digest &&
          state.verifications.last&.payload == source &&
          state.verifications.length == source.attempt_number &&
          prior.none? { _1.payload.evidence.outcome == "passed" } &&
          state.all_integrated? &&
          source.integration_events == state.successful_integrations.map(&:event) &&
          state.activation.nil? && state.compensation_request.nil? && state.completion.nil? &&
          !(source.evidence.outcome == "passed" &&
            source.evidence.findings.any? { %w[error critical].include?(_1.severity) }) &&
          @digest_builder.call(
            :verification,
            release_set_id: source.release_set_id,
            release_digest: source.release_digest,
            attempt_number: source.attempt_number,
            integration_events: source.integration_events,
            evidence: source.evidence,
            policy_version: source.policy_version
          ) == source.verification_digest
      end

      def valid_activation?(source, context:, state:)
        preparation = context.source_preparation
        verification = state.latest_verification
        source.release_set_id == preparation.release_set_id &&
          source.change_set_id == preparation.change_set_id &&
          source.release_digest == preparation.release_digest &&
          state.activation&.payload == source &&
          state.all_integrated? &&
          state.verified? &&
          source.verification_event == verification&.event &&
          source.verification_digest == verification&.payload&.verification_digest &&
          @digest_builder.call(
            :activation,
            release_set_id: source.release_set_id,
            release_digest: source.release_digest,
            verification_event: source.verification_event,
            verification_digest: source.verification_digest,
            activation_point: source.activation_point,
            policy_version: source.policy_version
          ) == source.activation_digest
      end

      def valid_compensation?(source, context:, state:)
        preparation = context.source_preparation
        trigger = state.integrations.find { _1.event == source.trigger_event } ||
                  state.verifications.find { _1.event == source.trigger_event }
        source.release_set_id == preparation.release_set_id &&
          source.change_set_id == preparation.change_set_id &&
          source.release_digest == preparation.release_digest &&
          state.compensation_request&.payload == source &&
          source.successful_integrations == state.successful_integrations.map(&:event) &&
          state.activation.nil? && state.completion.nil? &&
          compensation_trigger_valid?(trigger, source.trigger_kind, source.reason)
      end

      def compensation_trigger_valid?(trigger, trigger_kind, reason)
        case trigger
        when ReleaseSets::IntegrationFactV1
          trigger_kind == "repository_integration_failed" &&
            trigger.payload.outcome == "failed" &&
            reason == trigger.payload.failure&.summary
        when ReleaseSets::VerificationFactV1
          trigger_kind == "release_verification_failed" &&
            trigger.payload.evidence.outcome == "failed" &&
            reason == "Composite ReleaseSet verification failed"
        else false
        end
      end

      def valid_completion?(source, context:, state:)
        preparation = context.source_preparation
        return false unless source.release_set_id == preparation.release_set_id &&
                            source.change_set_id == preparation.change_set_id &&
                            source.release_digest == preparation.release_digest &&
                            state.completion&.payload == source

        expected_source, expected_evidence = if source.outcome == "activated"
          return false if state.compensation_request

          [ state.activation&.event, [] ]
        else
          return false if state.activation

          request = state.compensation_request
          expected = request&.payload&.successful_integrations || []
          actual = source.compensation_evidence.map(&:integration_event)
          return false unless expected == actual
          return false unless source.compensation_evidence.all? do |evidence|
            integration = state.integrations.find { _1.event == evidence.integration_event }
            integration&.payload&.repository_id == evidence.repository_id
          end

          [ request&.event, source.compensation_evidence ]
        end
        return false unless source.source_event == expected_source && source.compensation_evidence == expected_evidence

        @digest_builder.call(
          :completion,
          release_set_id: source.release_set_id,
          release_digest: source.release_digest,
          outcome: source.outcome,
          source_event: source.source_event,
          compensation_evidence: source.compensation_evidence,
          rule_version: source.rule_version
        ) == source.completion_digest
      end

      def transform_failure(source)
        return unless source

        ReleaseSets::IntegrationFailureV2.new(
          code: source.code,
          summary: source.summary,
          producer: source.producer,
          run_id: source.run_id,
          result_digest: source.result_digest
        )
      end

      def source_state(source_event:, source_upper_position:)
        events = @event_store.read(
          StreamReference.new(
            context: source_event.stream.context,
            stream_name: source_event.stream.stream_name,
            stream_id: source_event.stream.stream_id
          ),
          EventQueries::RELEASE_SET_LIFECYCLE
        ).select do |event|
          event.stream_revision <= source_event.stream_revision &&
            event.global_position <= source_upper_position
        end
        unless events.map(&:stream_revision) == (0..source_event.stream_revision).to_a &&
            events.last&.id == source_event.id &&
            events.map(&:correlation_id).uniq.one? &&
            events.all? do |event|
              event.metadata["schema_version"] == 1 &&
                event.markers.include?("release-set:#{source_event.stream.stream_id}")
            end
          return Failure(inconsistent(source_event, "ReleaseSet source history is incomplete or non-contiguous"))
        end

        facts = {
          preparation: nil,
          integrations: [],
          verifications: [],
          activation: nil,
          compensation_request: nil,
          completion: nil
        }
        events.each do |event|
          payload = load(event)
          unless payload.release_set_id == source_event.stream.stream_id
            return Failure(inconsistent(source_event, "ReleaseSet event identity does not match its stream"))
          end

          reference = event_reference(event)
          case payload
          when Events::ReleaseSetPreparedV1
            return Failure(inconsistent(source_event, "duplicate ReleaseSet preparation")) if facts[:preparation]

            facts[:preparation] = ReleaseSets::PreparationFactV1.new(
              payload:,
              event: reference,
              correlation_id: event.correlation_id
            )
          when Events::RepositoryIntegrationRecordedV1
            facts[:integrations] << ReleaseSets::IntegrationFactV1.new(payload:, event: reference)
          when Events::ReleaseSetVerificationRecordedV1
            facts[:verifications] << ReleaseSets::VerificationFactV1.new(payload:, event: reference)
          when Events::ReleaseSetActivatedV1
            return Failure(inconsistent(source_event, "duplicate ReleaseSet activation")) if facts[:activation]

            facts[:activation] = ReleaseSets::ActivationFactV1.new(payload:, event: reference)
          when Events::ReleaseSetCompensationRequestedV1
            if facts[:compensation_request]
              return Failure(inconsistent(source_event, "duplicate ReleaseSet compensation request"))
            end

            facts[:compensation_request] = ReleaseSets::CompensationRequestFactV1.new(
              payload:,
              event: reference
            )
          when Events::ReleaseSetCompletedV1
            return Failure(inconsistent(source_event, "duplicate ReleaseSet completion")) if facts[:completion]

            facts[:completion] = ReleaseSets::CompletionFactV1.new(payload:, event: reference)
          else
            return Failure(inconsistent(source_event, "unsupported fact in ReleaseSet source stream"))
          end
        end
        unless facts[:preparation]
          return Failure(inconsistent(source_event, "ReleaseSet source history has no preparation"))
        end

        Success(Domain::ReleaseSets::LifecycleStateV1.new(**facts))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
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

      def fact(context:, event:, markers:, step_name:, metadata_extension: nil)
        TransformedFactV1.new(
          target_stream: context.target_stream,
          event:,
          markers:,
          step_name:,
          metadata_extension:
        )
      end

      def actor_metadata(source_event, **attributes)
        attributes[:policy_version] ||= source_event.metadata["policy_version"]
        MigrationMetadataExtensionV1.new(
          attributed_actor: Commands::Actor.new(
            kind: source_event.metadata.fetch("actor_kind"),
            id: source_event.metadata.fetch("actor_id")
          ),
          **attributes
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "ReleaseSet transformation is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
