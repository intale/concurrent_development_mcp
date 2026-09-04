# frozen_string_literal: true

module Coordinator::Processes
  module ReleaseSetLifecycle
    class CommandBuilder
      ACTOR = Coordinator::Write::Commands::Actor.new(kind: "system", id: "release-set-lifecycle")
      COMPENSATION_RULE_VERSION = "release-set-compensation/v1"
      COMPLETION_RULE_VERSION = "release-set-completion/v1"

      def rule_version(source)
        case source.payload
        when Coordinator::Write::Events::RepositoryIntegrationRecordedV2
          COMPENSATION_RULE_VERSION if source.payload.outcome == "failed"
        when Coordinator::Write::Events::ReleaseSetVerificationRecordedV2
          COMPENSATION_RULE_VERSION if source.payload.evidence.outcome == "failed"
        when Coordinator::Write::Events::ReleaseSetActivatedV2
          COMPLETION_RULE_VERSION
        end
      end

      def call(source, command_id:)
        case rule_version(source)
        when COMPENSATION_RULE_VERSION then compensation(source, command_id:)
        when COMPLETION_RULE_VERSION then activated_completion(source, command_id:)
        end
      end

      private

      def compensation(source, command_id:)
        Coordinator::Write::Commands::RequestReleaseSetCompensation.new(
          command_id:,
          actor: ACTOR,
          release_set_id: source.payload.release_set_id,
          trigger_event: source.reference,
          rule_version: COMPENSATION_RULE_VERSION
        )
      end

      def activated_completion(source, command_id:)
        Coordinator::Write::Commands::CompleteActivatedReleaseSet.new(
          command_id:,
          actor: ACTOR,
          release_set_id: source.payload.release_set_id,
          activation_event: source.reference,
          rule_version: COMPLETION_RULE_VERSION
        )
      end
    end
  end
end
