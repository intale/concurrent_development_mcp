# frozen_string_literal: true

module Coordinator::Write
  module Domain::ProjectionInitialization
    class InitializeFacts
      def call(command:, state:)
        return [] if state.existing_types.length == state.definition.target_types.length

        metadata = EventMetadata.new(command_id: command.command_id, actor_kind: command.actor.kind,
          actor_id: command.actor.id, recorded_by: "coordinator", policy_version: "projection-initialization/v1")
        facts = case state.definition.source_type
        when "OperationBatchCreated" then batch(state, metadata:)
        when "VerificationObligationCreated" then verification(state, metadata:)
        when "DecisionActivated" then [ emission(Events::ProjectionNumbers::DecisionCorrectionsNumberChangedV1.new(
                  decision_id: state.stream.stream_id, corrections_number: state.corrections_number), metadata:) ]
        when "SkillRevisionCreated" then [ emission(Events::ProjectionNumbers::SkillRevisionRepresentationRecordedV1.new(
                  skill_revision_id: state.stream.stream_id), metadata: Metadata::SkillRevisionRepresentationV1.new(
                    **metadata.to_h, asset_count: state.history.map { _1.data.fetch("asset_id") }.uniq.length)) ]
        when "ReleaseSetPrepared" then release(state, metadata:)
        end
        facts.reject { state.existing_types.include?(_1.event.class.event_type) }
      end

      private

      def emission(event, metadata:)
        Coordinator::Write::ProjectionInitialization::Emission.new(event:, metadata:)
      end

      def batch(state, metadata:)
        id = state.stream.stream_id
        items = state.history.select { _1.type == "OperationBatchItemEnqueued" }.uniq { _1.data.fetch("index") }
        outcomes = state.history.select { %w[OperationBatchItemSucceeded OperationBatchItemRejected OperationBatchItemRegistrationRejected OperationBatchItemFailed].include?(_1.type) }
          .uniq { _1.data.fetch("index") }
        succeeded = outcomes.count { _1.type == "OperationBatchItemSucceeded" }
        unsuccessful = outcomes.length - succeeded
        facts = [
          emission(Events::ProjectionNumbers::OperationBatchManifestAcceptedV1.new(batch_id: id),
            metadata: Metadata::OperationBatchManifestV1.new(**metadata.to_h, item_count: items.length,
              encoded_byte_size: items.sum { |item| item.metadata.fetch("encoded_byte_size") { JSON.generate(item.data.fetch("input")).bytesize } })),
          emission(Events::ProjectionNumbers::OperationBatchSucceededItemsNumberChangedV1.new(batch_id: id, items_number: succeeded), metadata:),
          emission(Events::ProjectionNumbers::OperationBatchUnsuccessfulItemsNumberChangedV1.new(batch_id: id, items_number: unsuccessful), metadata:)
        ]
        terminal = state.history.find { %w[OperationBatchCompleted OperationBatchCancelled].include?(_1.type) }
        if terminal
          outcome = terminal.type == "OperationBatchCancelled" ? "cancelled" : (unsuccessful.positive? ? "completed_with_errors" : "completed")
          facts << emission(Events::ProjectionNumbers::OperationBatchOutcomeRecordedV1.new(batch_id: id, outcome:), metadata:)
        end
        facts
      end

      def verification(state, metadata:)
        evidence = state.history.uniq { _1.data.fetch("evidence_id") }
        required = state.source.data.fetch("required_evidence")
        accepted = evidence.select { _1.data.fetch("assessment").fetch("conclusion") == "passed" }.map { _1.data.fetch("evidence_kind") }
        passed = required.select { accepted.include?(_1) }
        [ emission(Events::ProjectionNumbers::VerificationObligationEvidenceNumberChangedV1.new(
          obligation_id: state.stream.stream_id, evidence_number: evidence.length), metadata:),
          emission(Events::ProjectionNumbers::VerificationObligationEvidenceCoverageChangedV1.new(
            obligation_id: state.stream.stream_id, passed_evidence_kinds: passed, missing_evidence_kinds: required - passed), metadata:) ]
      end

      def release(state, metadata:)
        return [] if state.history.any? { %w[ReleaseSetActivated ReleaseSetCompensationRequested ReleaseSetCompleted].include?(_1.type) }

        members = state.history.select { _1.type == "ReleaseSetMemberAdded" }.map { _1.data.fetch("repository_id") }
        integrated = state.history.select { _1.type == "RepositoryIntegrationRecorded" && _1.data.fetch("outcome") == "integrated" }
          .map { _1.data.fetch("repository_id") }
        linked = state.history.select { _1.type == "RepositoryIntegrationMergeLinked" }.map { _1.data.fetch("repository_id") }
        return [] if members.empty? || !members.all? { integrated.include?(_1) && linked.include?(_1) }

        [ emission(Events::ProjectionNumbers::ReleaseSetVerificationRequestedV1.new(release_set_id: state.stream.stream_id), metadata:) ]
      end
    end
  end
end
