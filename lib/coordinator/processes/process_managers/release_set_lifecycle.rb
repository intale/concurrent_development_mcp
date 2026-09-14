# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class ReleaseSetLifecycle
      HANDLED_COMPENSATION_CODES = %i[
        release_set_already_completed
        release_set_already_activated
        release_set_compensation_already_requested
        release_compensation_not_required
      ].freeze
      HANDLED_COMPLETION_CODES = %i[release_set_already_completed].freeze

      def initialize(
        event_store:,
        source_builder: Coordinator::Processes::ReleaseSetLifecycle::SourceBuilder.new,
        command_builder: Coordinator::Processes::ReleaseSetLifecycle::CommandBuilder.new,
        process_step_planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:),
        request_compensation: Coordinator::Write::Operations::ExecuteRequestReleaseSetCompensation.new(event_store:),
        complete_activated: Coordinator::Write::Operations::ExecuteCompleteActivatedReleaseSet.new(event_store:)
      )
        @source_builder = source_builder
        @command_builder = command_builder
        @process_step_planner = process_step_planner
        @request_compensation = request_compensation
        @complete_activated = complete_activated
      end

      def call(event)
        source = @source_builder.call(event)
        rule_version = @command_builder.rule_version(source)
        return unless rule_version

        step_name = rule_version == Coordinator::Processes::ReleaseSetLifecycle::CommandBuilder::COMPENSATION_RULE_VERSION ?
          "request-compensation" : "complete-activated-release-set"
        process_step = @process_step_planner.call(
          source_event: source.event,
          process_name: "release-set-lifecycle",
          step_name:,
          subject_kind: "release-set",
          subject_id: source.payload.release_set_id,
          rule_version:,
          allocate_target_entity: false
        )
        command = @command_builder.call(source, command_id: process_step.target_command_id)

        instrument_command_boundary(source, command)

        case command
        when Coordinator::Write::Commands::RequestReleaseSetCompensation
          execute!(
            @request_compensation.call_command(command, caused_by: process_step.event),
            handled_codes: HANDLED_COMPENSATION_CODES,
            transition: "request compensation",
            process_step:
          )
        when Coordinator::Write::Commands::CompleteActivatedReleaseSet
          execute!(
            @complete_activated.call_command(command, caused_by: process_step.event),
            handled_codes: HANDLED_COMPLETION_CODES,
            transition: "complete activated ReleaseSet",
            process_step:
          )
        end
        nil
      end

      private

      def instrument_command_boundary(source, command)
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: "release_set_lifecycle",
          command_id: source.event.metadata.fetch("command_id"),
          process_command_id: command.command_id,
          source_event_id: source.event.id
        )
      end

      def execute!(result, handled_codes:, transition:, process_step:)
        return result.value! if result.success?
        return if handled_codes.include?(result.failure.code)

        @process_step_planner.record_dispatch_failure(process_step:, failure: result.failure)
      end
    end
  end
end
