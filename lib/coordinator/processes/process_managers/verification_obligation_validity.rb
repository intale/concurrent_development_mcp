# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class VerificationObligationValidity
      HANDLED_START_CODES = [ :verification_obligation_validity_scan_already_decided ].freeze
      HANDLED_PROGRESS_CODES = [
        :verification_obligation_validity_scan_not_running,
        :verification_obligation_validity_scan_checkpoint_changed
      ].freeze
      HANDLED_INVALIDATION_CODES = [
        :verification_obligation_already_invalidated,
        :verification_obligation_policy_still_current
      ].freeze

      def initialize(
        event_store:,
        source_builder: Coordinator::Processes::VerificationObligationValidity::SourceBuilder.new(event_store:),
        partition_loader: Coordinator::Processes::VerificationObligationValidity::CurrentPartitionLoader.new(event_store:),
        checkpoint_loader: Coordinator::Processes::VerificationObligationValidity::CheckpointLoader.new(event_store:),
        page_reader: Coordinator::Processes::VerificationObligationValidity::PageReader.new(event_store:),
        command_builder: Coordinator::Processes::VerificationObligationValidity::CommandBuilder.new,
        start_scan: Coordinator::Write::Operations::ExecuteStartVerificationObligationValidityScan.new(event_store:),
        progress_scan: Coordinator::Write::Operations::ExecuteProgressVerificationObligationValidityScan.new(event_store:),
        invalidate: Coordinator::Write::Operations::ExecuteInvalidateVerificationObligation.new(event_store:)
      )
        @source_builder = source_builder
        @partition_loader = partition_loader
        @checkpoint_loader = checkpoint_loader
        @page_reader = page_reader
        @command_builder = command_builder
        @start_scan = start_scan
        @progress_scan = progress_scan
        @invalidate = invalidate
      end

      def call(event)
        source = @source_builder.call(event)
        case source.payload
        when Coordinator::Write::Events::DecisionPartitionAdvancedV1
          start_scan(source) if candidate_partition?(source.payload)
        when Coordinator::Write::Events::VerificationObligationCreatedV1
          repair_creation(source)
        when Coordinator::Write::Events::VerificationObligationValidityScanStartedV1,
             Coordinator::Write::Events::VerificationObligationValidityScanProgressedV1
          process_page(source)
        end
        nil
      end

      private

      def start_scan(source)
        execute!(
          @start_scan.call(@command_builder.start(source)),
          handled_codes: HANDLED_START_CODES,
          transition: "start scan"
        )
      end

      def repair_creation(source)
        partition = @partition_loader.call(source.payload.change_set_id)
        return unless partition
        return if partition.reference == source.payload.policy.partition_event

        invalidate(
          obligation_event: source.event,
          superseding_partition_event: partition.reference,
          caused_by_event: source.event,
          caused_by_reference: source.reference
        )
      end

      def process_page(source)
        checkpoint = @checkpoint_loader.call(source)
        return unless checkpoint

        page = @page_reader.call(checkpoint)
        page.obligations.each do |obligation|
          invalidate(
            obligation_event: obligation,
            superseding_partition_event: checkpoint.superseding_partition_event,
            caused_by_event: checkpoint.event,
            caused_by_reference: checkpoint.reference
          )
        end
        execute!(
          @progress_scan.call(@command_builder.progress(checkpoint:, page:)),
          handled_codes: HANDLED_PROGRESS_CODES,
          transition: "progress scan"
        )
      end

      def invalidate(obligation_event:, superseding_partition_event:, caused_by_event:, caused_by_reference:)
        invocation = @command_builder.invalidation(
          obligation_event:,
          superseding_partition_event:,
          caused_by_event:,
          caused_by_reference:
        )
        execute!(
          @invalidate.call(invocation),
          handled_codes: HANDLED_INVALIDATION_CODES,
          transition: "invalidate obligation"
        )
      end

      def candidate_partition?(partition_event)
        partition = partition_event.partition
        partition.topic_root == "candidate" &&
          partition.anchor_kind == "changeset" &&
          partition.partition_id == "changeset:#{partition.anchor_id}:candidate"
      end

      def execute!(result, handled_codes:, transition:)
        return result.value! if result.success?
        return if handled_codes.include?(result.failure.code)

        failure = result.failure
        raise VerificationObligationValidityProcessRejected,
              "Validity process #{transition} rejected: #{failure.code} - #{failure.message}"
      end
    end
  end
end
