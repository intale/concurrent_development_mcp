# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class VerificationPolicyV1Transformer
      include Dry::Monads[:result]

      def initialize(partition_reference_resolver:, head_reference_resolver:)
        @partition_reference_resolver = partition_reference_resolver
        @head_reference_resolver = head_reference_resolver
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        policy:,
        source_change_set_id:,
        target_change_set_id:
      )
        unless policy.change_set_id == source_change_set_id
          return Failure(inconsistent(source_event, "policy identifies another ChangeSet"))
        end

        partition = @partition_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: policy.partition_event
        )
        return partition if partition.failure?

        target_partition_event, partition_payload, target_partition = partition.value!
        unless partition_payload.partition == policy.partition &&
            partition_payload.active_decisions.include?(policy.head)
          return Failure(inconsistent(source_event, "policy partition evidence disagrees with its source fact"))
        end

        head = @head_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          head: policy.head
        )
        return head if head.failure?

        Success(
          CandidateObligations::ImpactPolicyEvidenceV1.new(
            policy.to_h.merge(
              partition_event: target_partition_event,
              partition: target_partition,
              head: head.value!,
              change_set_id: target_change_set_id
            )
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Verification policy migration is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
