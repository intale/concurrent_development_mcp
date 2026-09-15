# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class ChangeSetV1Transformer
      include Dry::Monads[:result]

      def initialize(stream_identity_allocator:, entity_reference_resolver:)
        @stream_identity_allocator = stream_identity_allocator
        @entity_reference_resolver = entity_reference_resolver
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "DevelopmentPlanning",
          target_stream_name: "ChangeSet",
          identity_role: "change-set"
        )
        return allocation if allocation.failure?

        target_stream = allocation.value!.target_stream
        change_set_id = target_stream.stream_id
        case source_payload
        when Events::ChangeSetCreatedV1
          Success(created_facts(source_payload, target_stream:, change_set_id:))
        when Events::ChangeSetAcceptanceCriteriaDefinedV1
          Success([
            fact(
              target_stream:,
              event: Events::ChangeSetAcceptanceCriteriaDefinedV2.new(
                change_set_id:,
                acceptance_criteria: source_payload.acceptance_criteria
              ),
              markers: markers(change_set_id),
              step_name: "define-change-set-acceptance-criteria"
            )
          ])
        when Events::ChangeSetActivatedV1
          Success([
            fact(
              target_stream:,
              event: Events::ChangeSetActivatedV2.new(change_set_id:),
              markers: markers(change_set_id),
              step_name: "activate-change-set"
            )
          ])
        when Events::ChangeSetCompletedV1
          completed_facts(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload,
            target_stream:,
            change_set_id:
          )
        end
      end

      private

      def created_facts(source, target_stream:, change_set_id:)
        [
          fact(
            target_stream:,
            event: Events::ChangeSetCreatedV2.new(change_set_id:),
            markers: markers(change_set_id),
            step_name: "create-change-set"
          ),
          fact(
            target_stream:,
            event: Events::ChangeSetGoalDefinedV1.new(change_set_id:, goal: source.goal),
            markers: markers(change_set_id),
            step_name: "define-change-set-goal"
          )
        ]
      end

      def completed_facts(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:,
        change_set_id:
      )
        facts = []
        if source.release_set_completion_event
          release_set = resolve_release_set(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_reference: source.release_set_completion_event
          )
          return release_set if release_set.failure?

          release_set_id = release_set.value!.target_stream.stream_id
          facts << fact(
            target_stream:,
            event: Events::ChangeSetReleaseSetLinkedV1.new(change_set_id:, release_set_id:),
            markers: markers(change_set_id) + [ "release-set:#{release_set_id}" ],
            step_name: "link-change-set-release-set",
            policy_version: source.rule_version
          )
        end
        facts << fact(
          target_stream:,
          event: Events::ChangeSetCompletedV2.new(change_set_id:),
          markers: markers(change_set_id),
          step_name: "complete-change-set",
          policy_version: source.rule_version
        )
        Success(facts)
      end

      def resolve_release_set(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:
      )
        @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: source_reference.stream_context,
            stream_name: source_reference.stream_name,
            stream_id: source_reference.stream_id
          ),
          target_stream_context: "DevelopmentIntegration",
          target_stream_name: "ReleaseSet",
          identity_role: "release-set"
        )
      end

      def fact(target_stream:, event:, markers:, step_name:, policy_version: nil)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension: policy_version && MigrationMetadataExtensionV1.new(policy_version:)
        )
      end

      def markers(change_set_id)
        [ "change-set:#{change_set_id}" ]
      end
    end
  end
end
