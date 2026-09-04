# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class DependencySatisfactionSource < Dry::Validation::Contract
      WORK_ITEM_SOURCES = [
        Events::WorkItemCandidateSelectedV1,
        Events::WorkItemCandidateSelectedV2,
        Events::WorkItemCompletedV1,
        Events::WorkItemCompletedV2
      ].freeze
      RELEASE_SET_SOURCES = [
        Events::RepositoryIntegrationRecordedV2,
        Events::ReleaseSetVerificationRecordedV2,
        Events::ReleaseSetCompletedV2
      ].freeze

      params do
        required(:evidence).value(Types.Instance(DependencySatisfactions::SourceEvidenceV1))
        required(:command).value(Types.Instance(Commands::SatisfyWorkItemDependency))
        required(:dependency).value(Types.Instance(Domain::ChangeSets::Dependency))
      end

      rule(:evidence, :command, :dependency) do
        evidence = values[:evidence]
        command = values[:command]
        dependency = values[:dependency]
        event = evidence.event
        reference = evidence.reference
        payload = evidence.payload

        key(:evidence).failure("must match the command source reference") unless reference == command.source_event
        unless event.id == reference.event_id && event.type == reference.type &&
               event.stream.context == reference.stream_context &&
               event.stream.stream_name == reference.stream_name &&
               event.stream.stream_id == reference.stream_id &&
               event.stream_revision == reference.stream_revision
          key(:evidence).failure("physical event identity must match its source reference")
        end
        unless Types::UUID_V7_PATTERN.match?(event.correlation_id.to_s)
          key(:evidence).failure("must carry a pg_eventstore trace correlation ID")
        end
        unless evidence.producer_state.work_item_id == dependency.producer_work_item_id
          key(:evidence).failure("must load the declared producer WorkItem")
        end

        if WORK_ITEM_SOURCES.any? { payload.is_a?(_1) }
          validate_work_item_source(key, evidence:, payload:, command:)
        elsif RELEASE_SET_SOURCES.any? { payload.is_a?(_1) }
          validate_release_set_source(key, evidence:, payload:, command:)
        else
          key(:evidence).failure("event type is not a dependency-satisfaction source")
        end
      end

      private

      def validate_work_item_source(key, evidence:, payload:, command:)
        change_set_id = if payload.is_a?(Events::WorkItemCompletedV2)
          evidence.producer_state.change_set_id
        else
          payload.change_set_id
        end
        unless evidence.reference.stream_context == "DevelopmentExecution" &&
               evidence.reference.stream_name == "WorkItem" &&
               evidence.reference.stream_id == payload.work_item_id &&
               change_set_id == command.change_set_id &&
               evidence.release_state.nil?
          key(:evidence).failure("WorkItem source scope is inconsistent")
        end
      end

      def validate_release_set_source(key, evidence:, payload:, command:)
        unless evidence.reference.stream_context == "DevelopmentIntegration" &&
               evidence.reference.stream_name == "ReleaseSet" &&
               evidence.reference.stream_id == payload.release_set_id &&
               evidence.release_state&.preparation&.payload&.change_set_id == command.change_set_id
          key(:evidence).failure("ReleaseSet source scope is inconsistent")
        end
      end
    end
  end
end
