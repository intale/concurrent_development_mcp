# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class CorrelationResolver
      def initialize(release_set_correlation_loader:)
        @release_set_correlation_loader = release_set_correlation_loader
      end

      def call(command)
        case command
        when Commands::RecordRepositoryIntegration,
             Commands::RecordReleaseSetVerification,
             Commands::RecordReleaseSetActivation,
             Commands::CompleteCompensatedReleaseSet
          @release_set_correlation_loader.call(command.release_set_id)
        end
      end
    end
  end
end
