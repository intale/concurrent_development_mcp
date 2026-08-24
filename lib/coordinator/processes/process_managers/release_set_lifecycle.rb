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
        request_compensation: Coordinator::Write::Operations::ExecuteRequestReleaseSetCompensation.new(event_store:),
        complete_activated: Coordinator::Write::Operations::ExecuteCompleteActivatedReleaseSet.new(event_store:)
      )
        @source_builder = source_builder
        @command_builder = command_builder
        @request_compensation = request_compensation
        @complete_activated = complete_activated
      end

      def call(event)
        source = @source_builder.call(event)
        command = @command_builder.call(source)
        return unless command

        case command
        when Coordinator::Write::Commands::RequestReleaseSetCompensation
          execute!(
            @request_compensation.call_command(command, caused_by: source.event),
            handled_codes: HANDLED_COMPENSATION_CODES,
            transition: "request compensation"
          )
        when Coordinator::Write::Commands::CompleteActivatedReleaseSet
          execute!(
            @complete_activated.call_command(command, caused_by: source.event),
            handled_codes: HANDLED_COMPLETION_CODES,
            transition: "complete activated ReleaseSet"
          )
        end
        nil
      end

      private

      def execute!(result, handled_codes:, transition:)
        return result.value! if result.success?
        return if handled_codes.include?(result.failure.code)

        failure = result.failure
        raise ReleaseSetLifecycleProcessRejected,
              "ReleaseSet lifecycle process could not #{transition}: #{failure.code} - #{failure.message}"
      end
    end
  end
end
