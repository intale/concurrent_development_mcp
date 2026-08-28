# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class CandidateImpactObligationPolicy
      HANDLED_REGISTRY_START_CODES = [ :candidate_impact_registry_sweep_already_decided ].freeze
      HANDLED_PAIR_START_CODES = [ :candidate_impact_pair_scan_already_decided ].freeze
      HANDLED_REGISTRY_PROGRESS_CODES = [
        :candidate_impact_registry_sweep_not_running,
        :candidate_impact_registry_sweep_checkpoint_changed,
        :candidate_impact_scan_concurrency_conflict
      ].freeze
      HANDLED_PAIR_PROGRESS_CODES = [
        :candidate_impact_pair_scan_not_running,
        :candidate_impact_pair_scan_checkpoint_changed,
        :candidate_impact_scan_concurrency_conflict
      ].freeze

      def initialize(
        event_store:,
        source_builder: CandidateObligations::SourceBuilder.new(event_store:),
        policy_observer: CandidateObligations::PolicyObserver.new(event_store:),
        checkpoint_loader: CandidateObligations::CheckpointLoader.new(event_store:),
        page_reader: CandidateObligations::PageReader.new(event_store:),
        command_builder: CandidateObligations::CommandBuilder.new(event_store:),
        start_registry_sweep: Coordinator::Write::Operations::ExecuteStartCandidateImpactRegistrySweep.new(event_store:),
        progress_registry_sweep: Coordinator::Write::Operations::ExecuteProgressCandidateImpactRegistrySweep.new(event_store:),
        start_pair_scan: Coordinator::Write::Operations::ExecuteStartCandidateImpactPairScan.new(event_store:),
        progress_pair_scan: Coordinator::Write::Operations::ExecuteProgressCandidateImpactPairScan.new(event_store:),
        create_obligation: Coordinator::Write::Operations::ExecuteCreateCandidateCompatibilityObligation.new(event_store:)
      )
        @source_builder = source_builder
        @policy_observer = policy_observer
        @checkpoint_loader = checkpoint_loader
        @page_reader = page_reader
        @command_builder = command_builder
        @start_registry_sweep = start_registry_sweep
        @progress_registry_sweep = progress_registry_sweep
        @start_pair_scan = start_pair_scan
        @progress_pair_scan = progress_pair_scan
        @create_obligation = create_obligation
      end

      def call(event)
        source = @source_builder.call(event)
        case source.payload
        when Coordinator::Write::Events::DecisionPartitionAdvancedV1
          start_registry_sweep(source)
        when Coordinator::Write::Events::CandidateImpactSurfaceRegisteredV1
          start_registration_pairs(source)
        when Coordinator::Write::Events::CandidateImpactRegistrySweepStartedV1,
             Coordinator::Write::Events::CandidateImpactRegistrySweepProgressedV1
          process_registry_page(source)
        when Coordinator::Write::Events::CandidateImpactPairScanStartedV1,
             Coordinator::Write::Events::CandidateImpactPairScanProgressedV1
          process_pair_page(source)
        end
        nil
      end

      private

      def start_registry_sweep(source)
        trigger = @policy_observer.from_partition(source)
        return unless trigger

        execute!(
          @start_registry_sweep.call(@command_builder.registry_start(trigger:, source:)),
          handled_codes: HANDLED_REGISTRY_START_CODES,
          transition: "start registry sweep"
        )
      end

      def start_registration_pairs(source)
        trigger = @policy_observer.current_for_registration(source)
        return unless trigger

        start_pairs(registration: source.event, trigger:, caused_by: source)
      end

      def process_registry_page(source)
        checkpoint = @checkpoint_loader.registry(source)
        return unless checkpoint

        page = @page_reader.registry(checkpoint)
        trigger = trigger_for(checkpoint.state)
        page.registrations.each do |registration|
          start_pairs(registration:, trigger:, caused_by: checkpoint)
        end
        execute!(
          @progress_registry_sweep.call(@command_builder.registry_progress(checkpoint:, page:)),
          handled_codes: HANDLED_REGISTRY_PROGRESS_CODES,
          transition: "progress registry sweep"
        )
      end

      def process_pair_page(source)
        checkpoint = @checkpoint_loader.pair(source)
        return unless checkpoint

        page = @page_reader.pair(checkpoint)
        page.registrations.each do |registration|
          execute!(
            @create_obligation.call(
              @command_builder.obligation(
                checkpoint:,
                target_registration: registration
              )
            ),
            handled_codes: [],
            transition: "create compatibility obligation"
          )
        end
        execute!(
          @progress_pair_scan.call(@command_builder.pair_progress(checkpoint:, page:)),
          handled_codes: HANDLED_PAIR_PROGRESS_CODES,
          transition: "progress pair scan"
        )
      end

      def start_pairs(registration:, trigger:, caused_by:)
        %w[outgoing incoming].each do |direction|
          execute!(
            @start_pair_scan.call(
              @command_builder.pair_start(
                registration:,
                direction:,
                trigger:,
                caused_by:
              )
            ),
            handled_codes: HANDLED_PAIR_START_CODES,
            transition: "start #{direction} pair scan"
          )
        end
      end

      def trigger_for(state)
        CandidateObligations::PolicyTriggerV1.new(
          change_set_id: state.change_set_id,
          partition_event: state.policy_partition_event,
          head: state.policy_head
        )
      end

      def execute!(result, handled_codes:, transition:)
        return result.value! if result.success?
        return if handled_codes.include?(result.failure.code)

        failure = result.failure
        raise CandidateObligationProcessRejected,
              "Candidate-obligation #{transition} rejected: #{failure.code} - #{failure.message}"
      end
    end
  end
end
