# frozen_string_literal: true

module Coordinator::Processes
  module CandidateObligations
    class CommandBuilder
      ACTOR = Coordinator::Write::Commands::Actor.new(
        kind: "system",
        id: "candidate-impact-obligation-policy"
      )
      REGISTRY_RULE_VERSION = "candidate-impact-registry-sweep/v1"
      PAIR_RULE_VERSION = "candidate-impact-pair-scan/v1"
      OBLIGATION_RULE_VERSION = "candidate-compatibility-obligation/v1"
      INDEX_POLICY_VERSION = "candidate-impact-bucket-index/v1"
      PAGE_SIZE = 50

      def initialize(
        event_store:,
        identity_builder: Coordinator::Write::CandidateObligationScans::IdentityBuilder.new,
        obligation_identity_builder: Coordinator::Write::CandidateObligations::IdentityBuilder.new,
        candidate_loader: Coordinator::Write::CandidateObligations::CandidateEvidenceLoader.new(event_store:),
        reference_builder: EventReferenceBuilder.new
      )
        @identity_builder = identity_builder
        @obligation_identity_builder = obligation_identity_builder
        @candidate_loader = candidate_loader
        @reference_builder = reference_builder
      end

      def registry_start(trigger:, source:)
        scan_id = @identity_builder.registry_sweep(
          policy_partition_event: trigger.partition_event,
          policy_head: trigger.head,
          rule_version: REGISTRY_RULE_VERSION
        )
        command = Coordinator::Write::Commands::StartCandidateImpactRegistrySweep.new(
          command_id: scan_id,
          actor: ACTOR,
          scan_id:,
          change_set_id: trigger.change_set_id,
          policy_partition_event: trigger.partition_event,
          policy_head: trigger.head,
          from_revision: 0,
          page_size: PAGE_SIZE,
          rule_version: REGISTRY_RULE_VERSION
        )
        Coordinator::Write::CandidateImpactRegistrySweepInvocation.new(
          command:,
          source_event: source.event,
          source_reference: source.reference
        )
      end

      def pair_start(registration:, direction:, trigger:, caused_by:)
        registration_reference = @reference_builder.call(registration)
        scan_id = @identity_builder.pair_scan(
          source_registration: registration_reference,
          direction:,
          policy_partition_event: trigger.partition_event,
          policy_head: trigger.head,
          rule_version: PAIR_RULE_VERSION
        )
        command = Coordinator::Write::Commands::StartCandidateImpactPairScan.new(
          command_id: scan_id,
          actor: ACTOR,
          scan_id:,
          change_set_id: trigger.change_set_id,
          source_registration: registration_reference,
          direction:,
          policy_partition_event: trigger.partition_event,
          policy_head: trigger.head,
          from_revision: 0,
          to_revision: registration_reference.stream_revision - 1,
          page_size: PAGE_SIZE,
          index_policy_version: INDEX_POLICY_VERSION,
          rule_version: PAIR_RULE_VERSION
        )
        Coordinator::Write::CandidateImpactPairScanInvocation.new(
          command:,
          source_event: caused_by.event,
          source_reference: caused_by.reference
        )
      end

      def registry_progress(checkpoint:, page:)
        state = checkpoint.state
        command = Coordinator::Write::Commands::ProgressCandidateImpactRegistrySweep.new(
          command_id: progress_id(checkpoint.reference, state.rule_version),
          actor: ACTOR,
          scan_id: state.scan_id,
          change_set_id: state.change_set_id,
          policy_partition_event: state.policy_partition_event,
          policy_head: state.policy_head,
          expected_checkpoint: checkpoint.reference,
          previous_from_revision: state.from_revision,
          last_processed_revision: page.last_processed_revision,
          page_registration_count: page.registrations.length,
          has_more: page.has_more,
          page_size: state.page_size,
          rule_version: state.rule_version
        )
        Coordinator::Write::CandidateImpactRegistrySweepProgressInvocation.new(
          command:,
          checkpoint_event: checkpoint.event,
          checkpoint_reference: checkpoint.reference
        )
      end

      def pair_progress(checkpoint:, page:)
        state = checkpoint.state
        command = Coordinator::Write::Commands::ProgressCandidateImpactPairScan.new(
          command_id: progress_id(checkpoint.reference, state.rule_version),
          actor: ACTOR,
          scan_id: state.scan_id,
          change_set_id: state.change_set_id,
          source_registration: state.source_registration,
          direction: state.direction,
          policy_partition_event: state.policy_partition_event,
          policy_head: state.policy_head,
          expected_checkpoint: checkpoint.reference,
          previous_from_revision: state.from_revision,
          last_processed_revision: page.last_processed_revision,
          page_registration_count: page.registrations.length,
          has_more: page.has_more,
          page_size: state.page_size,
          index_policy_version: state.index_policy_version,
          rule_version: state.rule_version
        )
        Coordinator::Write::CandidateImpactPairScanProgressInvocation.new(
          command:,
          checkpoint_event: checkpoint.event,
          checkpoint_reference: checkpoint.reference
        )
      end

      def obligation(checkpoint:, target_registration:)
        state = checkpoint.state
        target_reference = @reference_builder.call(target_registration)
        source_reference, destination_reference = ordered_pair(
          state.source_registration,
          target_reference,
          state.direction
        )
        source = @candidate_loader.call(source_reference)
        target = @candidate_loader.call(destination_reference)
        identity = @obligation_identity_builder.call(
          source:,
          target:,
          policy_head: state.policy_head,
          rule_version: OBLIGATION_RULE_VERSION
        )
        command = Coordinator::Write::Commands::CreateCandidateCompatibilityObligation.new(
          command_id: identity.obligation_id,
          actor: ACTOR,
          obligation_id: identity.obligation_id,
          source_registration: source_reference,
          target_registration: destination_reference,
          policy_partition_event: state.policy_partition_event,
          policy_head: state.policy_head,
          rule_version: OBLIGATION_RULE_VERSION
        )
        Coordinator::Write::CandidateCompatibilityObligationInvocation.new(
          command:,
          caused_by: checkpoint.event,
          caused_by_reference: checkpoint.reference
        )
      end

      private

      def progress_id(checkpoint, rule_version)
        @identity_builder.progress(checkpoint_event: checkpoint, rule_version:)
      end

      def ordered_pair(source, target, direction)
        direction == "outgoing" ? [ source, target ] : [ target, source ]
      end
    end
  end
end
