# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ChangeSets
      class SatisfyWorkItemDependency
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(change_set_state:, consumer_state:, command:, evidence:, satisfied_at:)
          dependency = change_set_state.dependencies.find { _1.dependency_id == command.dependency_id }
          denial = denied(
            change_set_state:,
            consumer_state:,
            command:,
            evidence:,
            dependency:
          )
          return denial if denial

          satisfaction = Events::WorkItemDependencySatisfiedV1.new(
            change_set_id: command.change_set_id,
            dependency_id: dependency.dependency_id,
            producer_work_item_id: dependency.producer_work_item_id,
            consumer_work_item_id: dependency.consumer_work_item_id,
            dependency_kind: dependency.dependency_kind,
            required_output: dependency.required_output,
            source_event: evidence.reference,
            rule_version: command.rule_version,
            satisfied_at:
          )
          writes = [
            EventWrite.new(
              stream: @stream_factory.change_set(command.change_set_id),
              event: satisfaction
            )
          ]
          if ready_after?(change_set_state:, dependency:, consumer_state:)
            writes << EventWrite.new(
              stream: @stream_factory.work_item(dependency.consumer_work_item_id),
              event: Events::WorkItemMadeReadyV1.new(
                change_set_id: command.change_set_id,
                work_item_id: dependency.consumer_work_item_id,
                readiness_decision_id: command.command_id,
                reason: "dependencies_satisfied",
                made_ready_at: satisfied_at
              )
            )
          end

          Success(EventPlan.new(writes:))
        end

        private

        def denied(change_set_state:, consumer_state:, command:, evidence:, dependency:)
          return failure(:change_set_not_found, "ChangeSet does not exist", command) if change_set_state.absent?
          return failure(:change_set_not_active, "ChangeSet is not active", command) unless change_set_state.status == "active"
          return failure(:dependency_not_found, "Dependency is not declared", command) unless dependency

          if change_set_state.dependency_satisfied?(dependency.dependency_id)
            return failure(:dependency_already_satisfied, "Dependency already has a satisfaction fact", command)
          end
          unless consumer_state.change_set_id == command.change_set_id &&
                 consumer_state.work_item_id == dependency.consumer_work_item_id
            return failure(:consumer_work_item_mismatch, "Consumer WorkItem does not match the dependency", command)
          end
          unless source_matches?(dependency:, evidence:, change_set_id: command.change_set_id)
            failure(:dependency_source_mismatch, "Source event does not satisfy the declared dependency", command)
          end
        end

        def source_matches?(dependency:, evidence:, change_set_id:)
          producer = evidence.producer_state
          return false unless producer.work_item_id == dependency.producer_work_item_id
          return false unless producer.change_set_id == change_set_id

          case dependency.dependency_kind
          when "requires_candidate"
            candidate_source?(evidence.payload, dependency:, change_set_id:, producer:)
          when "requires_completion"
            completion_source?(evidence.payload, dependency:, change_set_id:, producer:)
          when "requires_artifact", "requires_contract"
            output_source?(evidence.payload, dependency:, change_set_id:, producer:)
          when "must_integrate_after"
            integration_source?(evidence, dependency:, change_set_id:, producer:)
          when "requires_composite_verification"
            verification_source?(evidence, dependency:, change_set_id:, producer:)
          when "must_deploy_after"
            deployment_source?(evidence, dependency:, change_set_id:, producer:)
          else
            false
          end
        end

        def candidate_source?(payload, dependency:, change_set_id:, producer:)
          payload.is_a?(Events::WorkItemCandidateSelectedV1) &&
            payload.change_set_id == change_set_id &&
            payload.work_item_id == dependency.producer_work_item_id &&
            payload.candidate_id == producer.selected_candidate_id
        end

        def completion_source?(payload, dependency:, change_set_id:, producer:)
          payload.is_a?(Events::WorkItemCompletedV1) &&
            payload.change_set_id == change_set_id &&
            payload.work_item_id == dependency.producer_work_item_id &&
            payload.candidate_id == producer.selected_candidate_id
        end

        def output_source?(payload, dependency:, change_set_id:, producer:)
          return false unless completion_source?(payload, dependency:, change_set_id:, producer:)

          payload.produced_outputs.any? do |output|
            output.kind == dependency.required_output&.kind && output.key == dependency.required_output&.key
          end
        end

        def integration_source?(evidence, dependency:, change_set_id:, producer:)
          payload = evidence.payload
          state = evidence.release_state
          return false unless payload.is_a?(Events::RepositoryIntegrationRecordedV1)
          return false unless payload.change_set_id == change_set_id && payload.outcome == "integrated"
          return false unless state&.integrations&.any? { _1.event == evidence.reference }

          member_contains_producer?(state.member(payload.repository_id), dependency:, producer:)
        end

        def verification_source?(evidence, dependency:, change_set_id:, producer:)
          payload = evidence.payload
          state = evidence.release_state
          return false unless payload.is_a?(Events::ReleaseSetVerificationRecordedV1)
          return false unless payload.change_set_id == change_set_id && payload.evidence.outcome == "passed"
          return false unless payload.evidence.run_id == dependency.required_output&.key
          return false unless state&.verifications&.any? { _1.event == evidence.reference }
          return false unless state.preparation

          state.preparation.payload.ordered_members.any? do |member|
            member_contains_producer?(member, dependency:, producer:)
          end
        end

        def deployment_source?(evidence, dependency:, change_set_id:, producer:)
          payload = evidence.payload
          state = evidence.release_state
          return false unless payload.is_a?(Events::ReleaseSetCompletedV1)
          return false unless payload.change_set_id == change_set_id && payload.outcome == "activated"
          return false unless state&.completion&.event == evidence.reference
          return false unless state.preparation

          state.preparation.payload.ordered_members.any? do |member|
            member_contains_producer?(member, dependency:, producer:)
          end
        end

        def member_contains_producer?(member, dependency:, producer:)
          return false unless member && producer.selected_candidate_id

          member.ordered_candidates.any? do |candidate|
            candidate.change_set_id == producer.change_set_id &&
              candidate.work_item_id == dependency.producer_work_item_id &&
              candidate.candidate_id == producer.selected_candidate_id
          end
        end

        def ready_after?(change_set_state:, dependency:, consumer_state:)
          return false unless consumer_state.status == "planned"

          incoming = change_set_state.dependencies.select do |candidate|
            candidate.consumer_work_item_id == dependency.consumer_work_item_id
          end
          incoming.all? do |candidate|
            candidate.dependency_id == dependency.dependency_id ||
              change_set_state.dependency_satisfied?(candidate.dependency_id)
          end
        end

        def failure(code, message, command)
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: {
                change_set_id: command.change_set_id,
                dependency_id: command.dependency_id,
                source_event_id: command.source_event.event_id
              }
            )
          )
        end
      end
    end
  end
end
