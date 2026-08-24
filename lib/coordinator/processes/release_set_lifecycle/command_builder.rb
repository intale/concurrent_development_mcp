# frozen_string_literal: true

module Coordinator::Processes
  module ReleaseSetLifecycle
    class CommandBuilder
      ACTOR = Coordinator::Write::Commands::Actor.new(kind: "system", id: "release-set-lifecycle")
      COMPENSATION_RULE_VERSION = "release-set-compensation/v1"
      COMPLETION_RULE_VERSION = "release-set-completion/v1"

      def call(source)
        case source.payload
        when Coordinator::Write::Events::RepositoryIntegrationRecordedV1
          compensation(source) if source.payload.outcome == "failed"
        when Coordinator::Write::Events::ReleaseSetVerificationRecordedV1
          compensation(source) if source.payload.evidence.outcome == "failed"
        when Coordinator::Write::Events::ReleaseSetActivatedV1
          activated_completion(source)
        end
      end

      private

      def compensation(source)
        Coordinator::Write::Commands::RequestReleaseSetCompensation.new(
          command_id: "release-compensation:v1:#{source.event.id}",
          actor: ACTOR,
          release_set_id: source.payload.release_set_id,
          trigger_event: source.reference,
          rule_version: COMPENSATION_RULE_VERSION
        )
      end

      def activated_completion(source)
        Coordinator::Write::Commands::CompleteActivatedReleaseSet.new(
          command_id: "release-completion:v1:#{source.event.id}",
          actor: ACTOR,
          release_set_id: source.payload.release_set_id,
          activation_event: source.reference,
          rule_version: COMPLETION_RULE_VERSION
        )
      end
    end
  end
end
