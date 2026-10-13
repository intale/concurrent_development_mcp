# frozen_string_literal: true

module Coordinator::Processes
  class TargetCommandExecutor
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        command_loader: Coordinator::Write::CommandLifecycle::Loader.new(event_store:),
        command_transition: Coordinator::Write::Operations::ApplyCommandTransition.new(
          event_store:,
          loader: command_loader
        ),
        succeed_command: Coordinator::Write::Domain::CommandLifecycles::Succeed.new,
        reject_command: Coordinator::Write::Domain::CommandLifecycles::Reject.new,
        fail_command: Coordinator::Write::Domain::CommandLifecycles::Fail.new,
        input_digest: Coordinator::Write::CommandInputDigest.new,
        id_generator: Coordinator::Write::IdGenerator.new,
        rejection_retryability: Coordinator::Write::Tasks::CommandRejectionRetryability.new,
        remove_resource: Coordinator::Write::Operations::ExecuteRemoveResource.new(event_store:),
        create_change_set: Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:),
        create_work_item: Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:),
        declare_work_item_dependency: Coordinator::Write::Operations::ExecuteDeclareWorkItemDependency.new(event_store:),
        activate_change_set: Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:),
        acquire_work_item: Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:),
        complete_work_item: Coordinator::Write::Operations::ExecuteCompleteWorkItem.new(event_store:),
        declare_work_intention_set: Coordinator::Write::Operations::ExecuteDeclareWorkIntentionSet.new(event_store:),
        expand_work_intention_set: Coordinator::Write::Operations::ExecuteExpandWorkIntentionSet.new(event_store:),
        renew_work_intention_set: Coordinator::Write::Operations::ExecuteRenewWorkIntentionSet.new(event_store:),
        withdraw_work_intention_set: Coordinator::Write::Operations::ExecuteWithdrawWorkIntentionSet.new(event_store:),
        record_guidance: Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:),
        propose_decision_interpretation: Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation.new(event_store:),
        adjudicate_decision_interpretation: Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation.new(event_store:),
        activate_decision: Coordinator::Write::Operations::ExecuteActivateDecision.new(event_store:),
        correct_decision: Coordinator::Write::Operations::ExecuteCorrectDecision.new(event_store:),
        record_agent_choice: Coordinator::Write::Operations::ExecuteRecordAgentChoice.new(event_store:),
        submit_candidate: Coordinator::Write::Operations::ExecuteSubmitCandidate.new(event_store:),
        submit_candidate_impact_surface:
          Coordinator::Write::Operations::ExecuteSubmitCandidateImpactSurface.new(event_store:),
        claim_verification_obligation:
          Coordinator::Write::Operations::ExecuteClaimVerificationObligation.new(event_store:),
        submit_compatibility_assessment:
          Coordinator::Write::Operations::ExecuteSubmitCompatibilityAssessment.new(event_store:),
        waive_verification_obligation:
          Coordinator::Write::Operations::ExecuteWaiveVerificationObligation.new(event_store:),
        register_merge_snapshot:
          Coordinator::Write::Operations::ExecuteRegisterMergeSnapshot.new(event_store:),
        submit_merge_snapshot_verification:
          Coordinator::Write::Operations::ExecuteSubmitMergeSnapshotVerification.new(event_store:),
        request_merge_authorization:
          Coordinator::Write::Operations::ExecuteRequestMergeAuthorization.new(event_store:),
        record_merge_observation:
          Coordinator::Write::Operations::ExecuteRecordMergeObservation.new(event_store:),
        prepare_release_set:
          Coordinator::Write::Operations::ExecutePrepareReleaseSet.new(event_store:),
        record_repository_integration:
          Coordinator::Write::Operations::ExecuteRecordRepositoryIntegration.new(event_store:),
        record_release_set_verification:
          Coordinator::Write::Operations::ExecuteRecordReleaseSetVerification.new(event_store:),
        record_release_set_activation:
          Coordinator::Write::Operations::ExecuteRecordReleaseSetActivation.new(event_store:),
        complete_compensated_release_set:
          Coordinator::Write::Operations::ExecuteCompleteCompensatedReleaseSet.new(event_store:),
        publish_skill_revision:
          Coordinator::Write::Operations::ExecutePublishSkillRevision.new(event_store:),
        capture_development_artifact:
          Coordinator::Write::Operations::ExecuteCaptureDevelopmentArtifact.new(event_store:),
        update_development_artifact:
          Coordinator::Write::Operations::ExecuteUpdateDevelopmentArtifact.new(event_store:),
        correct_development_artifact_classification:
          Coordinator::Write::Operations::ExecuteCorrectDevelopmentArtifactClassification.new(event_store:),
        declare_development_artifact_relation:
          Coordinator::Write::Operations::ExecuteDeclareDevelopmentArtifactRelation.new(event_store:),
        operation_batch_command:
          Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:)
      )
        @event_store = event_store
        @command_loader = command_loader
        @command_transition = command_transition
        @succeed_command = succeed_command
        @reject_command = reject_command
        @fail_command = fail_command
        @input_digest = input_digest
        @id_generator = id_generator
        @rejection_retryability = rejection_retryability
        @register_repository = Coordinator::Write::Operations::ExecuteRegisterRepository.new(event_store:)
        @resolve_resource = Coordinator::Write::Operations::ExecuteResolveResource.new(event_store:)
        @remove_resource = remove_resource
        @create_change_set = create_change_set
        @create_work_item = create_work_item
        @declare_work_item_dependency = declare_work_item_dependency
        @activate_change_set = activate_change_set
        @acquire_work_item = acquire_work_item
        @complete_work_item = complete_work_item
        @abandon_attempt = Coordinator::Write::Operations::ExecuteAbandonAttempt.new(event_store:)
        @declare_work_intention_set = declare_work_intention_set
        @expand_work_intention_set = expand_work_intention_set
        @renew_work_intention_set = renew_work_intention_set
        @withdraw_work_intention_set = withdraw_work_intention_set
        @record_guidance = record_guidance
        @propose_decision_interpretation = propose_decision_interpretation
        @adjudicate_decision_interpretation = adjudicate_decision_interpretation
        @activate_decision = activate_decision
        @correct_decision = correct_decision
        @record_agent_choice = record_agent_choice
        @submit_candidate = submit_candidate
        @submit_candidate_impact_surface = submit_candidate_impact_surface
        @claim_verification_obligation = claim_verification_obligation
        @submit_compatibility_assessment = submit_compatibility_assessment
        @waive_verification_obligation = waive_verification_obligation
        @register_merge_snapshot = register_merge_snapshot
        @submit_merge_snapshot_verification = submit_merge_snapshot_verification
        @request_merge_authorization = request_merge_authorization
        @record_merge_observation = record_merge_observation
        @prepare_release_set = prepare_release_set
        @record_repository_integration = record_repository_integration
        @record_release_set_verification = record_release_set_verification
        @record_release_set_activation = record_release_set_activation
        @complete_compensated_release_set = complete_compensated_release_set
        @publish_skill_revision = publish_skill_revision
        @capture_development_artifact = capture_development_artifact
        @update_development_artifact = update_development_artifact
        @correct_development_artifact_classification = correct_development_artifact_classification
        @declare_development_artifact_relation = declare_development_artifact_relation
        @create_operation_batch = operation_batch_command
        @cancel_operation_batch = operation_batch_command
      end

      def call(command, caused_by:)
        call_prepared(command, preparation: prepare(command, caused_by:), caused_by:)
      end

      def prepare(command, caused_by: nil)
        contract = Coordinator::Write::Tasks::TargetContractRegistry.fetch_for(command)
        contract.command_type[command]
        handler = instance_variable_get(contract.executor_variable)
        Coordinator::Write::Tasks::TargetPreparationV1.new(
          requested_digest: @input_digest.request(command),
          terminal_event_id: @id_generator.uuid_v7,
          handler_preparation: prepare_target(handler, command, caused_by:)
        )
      end

      def call_prepared(command, preparation:, caused_by:)
        contract = Coordinator::Write::Tasks::TargetContractRegistry.fetch_for(command)
        handler = instance_variable_get(contract.executor_variable)

        snapshot = @command_loader.call(command.command_id)
        validate_registration!(snapshot.state, command:, contract:, requested_digest: preparation.requested_digest)
        return Success(target_execution(snapshot)) if snapshot.state.terminal?
        if command.is_a?(Coordinator::Write::Commands::RenewWorkIntentionSet) ||
           command.is_a?(Coordinator::Write::Commands::CreateOperationBatch)
          return request_saga(handler, command, snapshot:, preparation:, contract:, caused_by:)
        end

        effects = committed_effects(command.command_id)
        return finish_success(command, preparation:, contract:, caused_by: effects.last) unless effects.empty?

        result, failure = execute_target(handler, command, preparation:, caused_by:)
        contract.receipt_type[result.value!.data] if result&.success?
        # Another delivery may have committed the atomic target before this one
        # observed a denial/conflict. Its durable facts win over that stale denial.
        effects = committed_effects(command.command_id)
        if result&.success? || !effects.empty?
          parent = effects.last || terminal_parent(result.value!, fallback: caused_by)
          return finish_success(command, preparation:, contract:, caused_by: parent)
        end

        transition = if failure
          transition_command(
            command, preparation:, contract:, caused_by:,
            outcome: Coordinator::Write::Commands::FailCommand.new(command_id: command.command_id, failure:),
            decider: @fail_command
          )
        else
          reject(command, error: result.failure, actor: command.actor, tool_name: contract.tool_name,
                 event_id: preparation.terminal_event_id, caused_by:)
        end
        execution_result(transition, command_id: command.command_id)
      end

      private

      def request_saga(handler, command, snapshot:, preparation:, contract:, caused_by:)
        if batch_request_recorded?(command)
          return Success(Coordinator::Write::Tasks::TargetExecution.new(command_state: snapshot.state, terminal_event: nil))
        end
        result, failure = execute_target(handler, command, preparation:, caused_by:)
        if result&.success? || batch_request_recorded?(command)
          return Success(Coordinator::Write::Tasks::TargetExecution.new(command_state: snapshot.state, terminal_event: nil))
        end
        transition = if failure
          transition_command(command, preparation:, contract:, caused_by:,
            outcome: Coordinator::Write::Commands::FailCommand.new(command_id: command.command_id, failure:), decider: @fail_command)
        else
          reject(command, error: result.failure, actor: command.actor, tool_name: contract.tool_name,
            event_id: preparation.terminal_event_id, caused_by:)
        end
        execution_result(transition, command_id: command.command_id)
      end

      def batch_request_recorded?(command)
        return false unless command.is_a?(Coordinator::Write::Commands::CreateOperationBatch)

        event = @event_store.read_marked(Coordinator::Write::StreamFactory.new.operation_batch(command.batch_id),
          Coordinator::Write::MarkedEventReadCriteria.new(event_type: "OperationBatchCreated",
            marker: "command:#{command.command_id}", maximum_count: 1, direction: :asc)).first
        return false unless event

        unless event.data.fetch("batch_id") == command.batch_id &&
               event.metadata.fetch("manifest_digest") == command.manifest_digest
          raise Coordinator::Write::InvalidCommandHistory, "Recorded Batch request differs from its canonical instruction"
        end
        true
      end

      def prepare_target(handler, command, caused_by:)
        case command
        when Coordinator::Write::Commands::CaptureDevelopmentArtifact, Coordinator::Write::Commands::DeclareDevelopmentArtifactRelation
          handler.prepare(command)
        when Coordinator::Write::Commands::CreateOperationBatch, Coordinator::Write::Commands::CancelOperationBatch
          handler.prepare(command, caused_by:)
        end
      end

      def target_execution(snapshot)
        Coordinator::Write::Tasks::TargetExecution.new(
          command_state: snapshot.state,
          terminal_event: snapshot.persisted_events.last
        )
      end

      def validate_registration!(state, command:, contract:, requested_digest:)
        unless state.command_id == command.command_id &&
               state.tool_name == contract.tool_name &&
               state.canonical_input_digest == requested_digest
          raise Coordinator::Write::InvalidCommandHistory,
                "Command registration does not match its submitted target input"
        end
      end

      def succeed(command, actor:, tool_name:, caused_by:, event_id:)
        @command_transition.call(
          command: Coordinator::Write::Commands::SucceedCommand.new(command_id: command.command_id),
          decider: @succeed_command,
          actor:,
          tool_name:,
          caused_by:,
          event_id:
        )
      end

      def reject(command, error:, actor:, tool_name:, caused_by:, event_id:)
        @command_transition.call(
          command: Coordinator::Write::Commands::RejectCommand.new(
            command_id: command.command_id,
            error: Coordinator::Write::Tasks::DomainErrorV1::Type[
              {
                code: error.code.to_s,
                message: error.message,
                details: error.details
              }
            ],
            retryable: @rejection_retryability.call(error)
          ),
          decider: @reject_command,
          actor:,
          tool_name:,
          caused_by:,
          event_id:
        )
      end

      def committed_effects(command_id)
        @event_store.read_command_events(Coordinator::Write::CommandEventReadCriteria.new(
          command_id:,
          through_global_position: Coordinator::Write::EventQueries::RESOURCE_BOUNDARY_MAXIMUM_GLOBAL_POSITION,
          maximum_count: Coordinator::Write::Types::OPERATION_BATCH_MAXIMUM_HISTORY_EVENTS
        ))
      end

      def execute_target(handler, command, preparation:, caused_by:)
        attempts = 0
        begin
          attempts += 1
          result = if preparation.handler_preparation
            handler.call_prepared_command(command, preparation: preparation.handler_preparation, caused_by:)
          else
            handler.call_command(command, caused_by:)
          end
          if result.failure? && result.failure.code == :concurrency_conflict
            # Command operations own their bounded reread/redecision attempts.
            # Do not multiply that budget by retrying an exhausted Result here.
            return execute_failure(result.failure.message, code: "concurrency_conflict", attempts: 3, retryable: true)
          else
            return [ result, nil ]
          end
        rescue PgEventstore::WrongExpectedRevisionError => error
          return execute_failure(error.message, code: "concurrency_conflict", attempts:, retryable: true) if attempts == 3
          retry_target = true
        rescue StandardError => error
          return execute_failure(error.message, code: "execution_error", attempts:, retryable: false)
        end while retry_target
      end

      def execute_failure(reason, code:, attempts:, retryable:)
        [ nil, Coordinator::Write::Tasks::ExecutionFailureV1.new(
          failed_step: "execute-target", reason_code: code, reason: reason[0, 2000],
          retryable:, effects_committed: false, attempts:
        ) ]
      end

      def transition_command(command, outcome:, decider:, preparation:, contract:, caused_by:)
        @command_transition.call(command: outcome, decider:, actor: command.actor,
                                 tool_name: contract.tool_name, caused_by:, event_id: preparation.terminal_event_id)
      end

      def finish_success(command, preparation:, contract:, caused_by:)
        execution_result(
          succeed(command, actor: command.actor, tool_name: contract.tool_name,
                  event_id: preparation.terminal_event_id, caused_by:),
          command_id: command.command_id
        )
      end

      def execution_result(transition, command_id:)
        if transition.failure?
          winner = @command_loader.call(command_id)
          return Success(target_execution(winner)) if winner.state.terminal?
          return transition
        end
        Success(Coordinator::Write::Tasks::TargetExecution.new(
          command_state: transition.value!.state, terminal_event: transition.value!.terminal_event
        ))
      end

      def terminal_parent(completion, fallback:)
        completion.terminal_event || fallback
      end
  end
end
