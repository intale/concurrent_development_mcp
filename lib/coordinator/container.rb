# frozen_string_literal: true

module Coordinator
  class Container < Dry::System::Container
    register("canonical_json", memoize: true) { Shared::CanonicalJson.new }
    register("compound_marker_builder", memoize: true) do
      Shared::CompoundMarkerBuilder.new(canonical_json: self["canonical_json"])
    end
    register("clock", memoize: true) { Shared::SystemClock.new }
    register("id_generator", memoize: true) { Shared::IdGenerator.new }
    register("stream_factory", memoize: true) { Write::StreamFactory.new }
    register("event_schema_registry", memoize: true) { Write::EventSchemaRegistry.new }
    register("interpretations.topic_registry", memoize: true) do
      Write::Interpretations::TopicRegistry.new
    end
    register("contracts.candidate_impact_policy_proposal", memoize: true) do
      Write::Contracts::CandidateImpactPolicyProposal.new
    end

    register("interpretations.slot_builder", memoize: true) do
      Write::Interpretations::InterpretationSlotBuilder.new(
        topic_registry: self["interpretations.topic_registry"],
        canonical_json: self["canonical_json"],
        compound_marker_builder: self["compound_marker_builder"]
      )
    end

    register("event_factory", memoize: true) do
      Write::EventFactory.new(registry: self["event_schema_registry"])
    end

    register("command_input_digest", memoize: true) do
      Write::CommandInputDigest.new(canonical_json: self["canonical_json"])
    end

    register("command_completion_builder", memoize: true) do
      Write::CommandCompletionBuilder.new
    end

    register("operations.prepare_create_change_set", memoize: true) do
      Write::Operations::PrepareCreateChangeSet.new
    end

    register("operations.prepare_create_work_item", memoize: true) do
      Write::Operations::PrepareCreateWorkItem.new
    end

    register("operations.prepare_declare_work_item_dependency", memoize: true) do
      Write::Operations::PrepareDeclareWorkItemDependency.new
    end

    register("operations.prepare_activate_change_set", memoize: true) do
      Write::Operations::PrepareActivateChangeSet.new
    end

    register("operations.prepare_acquire_work_item", memoize: true) do
      Write::Operations::PrepareAcquireWorkItem.new
    end

    register("operations.prepare_reserve_write_set", memoize: true) do
      Write::Operations::PrepareReserveWriteSet.new
    end

    register("operations.prepare_expand_write_set", memoize: true) do
      Write::Operations::PrepareExpandWriteSet.new
    end

    register("operations.prepare_renew_lease_set", memoize: true) do
      Write::Operations::PrepareRenewLeaseSet.new
    end

    register("operations.prepare_release_lease_set", memoize: true) do
      Write::Operations::PrepareReleaseLeaseSet.new
    end

    register("operations.prepare_record_guidance", memoize: true) do
      Write::Operations::PrepareRecordGuidance.new
    end

    register("operations.prepare_propose_decision_interpretation", memoize: true) do
      Write::Operations::PrepareProposeDecisionInterpretation.new(
        topic_policy_contract: self["contracts.candidate_impact_policy_proposal"]
      )
    end

    register("operations.prepare_adjudicate_decision_interpretation", memoize: true) do
      Write::Operations::PrepareAdjudicateDecisionInterpretation.new
    end

    register("operations.prepare_activate_decision", memoize: true) do
      Write::Operations::PrepareActivateDecision.new
    end

    register("operations.prepare_correct_decision", memoize: true) do
      Write::Operations::PrepareCorrectDecision.new
    end

    register("operations.prepare_record_agent_choice", memoize: true) do
      Write::Operations::PrepareRecordAgentChoice.new
    end

    register("operations.prepare_submit_candidate", memoize: true) do
      Write::Operations::PrepareSubmitCandidate.new
    end

    register("operations.prepare_submit_candidate_impact_surface", memoize: true) do
      Write::Operations::PrepareSubmitCandidateImpactSurface.new
    end

    register("domain.change_sets.create", memoize: true) do
      Write::Domain::ChangeSets::Create.new(stream_factory: self["stream_factory"])
    end

    register("domain.work_items.create", memoize: true) do
      Write::Domain::WorkItems::Create.new(stream_factory: self["stream_factory"])
    end

    register("domain.change_sets.declare_work_item_dependency", memoize: true) do
      Write::Domain::ChangeSets::DeclareWorkItemDependency.new(stream_factory: self["stream_factory"])
    end

    register("domain.change_sets.activate", memoize: true) do
      Write::Domain::ChangeSets::Activate.new(stream_factory: self["stream_factory"])
    end

    register("domain.work_items.evaluate_readiness", memoize: true) do
      Write::Domain::WorkItems::EvaluateReadiness.new(stream_factory: self["stream_factory"])
    end

    register("domain.work_items.acquire", memoize: true) do
      Write::Domain::WorkItems::Acquire.new(stream_factory: self["stream_factory"])
    end

    register("domain.resource_leases.reserve", memoize: true) do
      Write::Domain::ResourceLeases::Reserve.new(stream_factory: self["stream_factory"])
    end

    register("domain.resource_leases.expand", memoize: true) do
      Write::Domain::ResourceLeases::Expand.new(stream_factory: self["stream_factory"])
    end

    register("domain.resource_leases.renew", memoize: true) do
      Write::Domain::ResourceLeases::Renew.new(stream_factory: self["stream_factory"])
    end

    register("domain.resource_leases.release", memoize: true) do
      Write::Domain::ResourceLeases::Release.new(stream_factory: self["stream_factory"])
    end

    register("domain.resource_leases.expire", memoize: true) do
      Write::Domain::ResourceLeases::Expire.new(stream_factory: self["stream_factory"])
    end

    register("domain.guidance.record", memoize: true) do
      Write::Domain::Guidance::Record.new(stream_factory: self["stream_factory"])
    end

    register("domain.interpretations.propose", memoize: true) do
      Write::Domain::Interpretations::Propose.new(
        stream_factory: self["stream_factory"],
        topic_registry: self["interpretations.topic_registry"],
        topic_policy_contract: self["contracts.candidate_impact_policy_proposal"]
      )
    end

    register("domain.interpretations.adjudicate", memoize: true) do
      Write::Domain::Interpretations::Adjudicate.new(stream_factory: self["stream_factory"])
    end

    register("decisions.definition_builder", memoize: true) do
      Write::Decisions::DecisionDefinitionBuilder.new(
        topic_registry: self["interpretations.topic_registry"],
        canonical_json: self["canonical_json"]
      )
    end

    register("decisions.slot_builder", memoize: true) do
      Write::Decisions::DecisionSlotBuilder.new(
        canonical_json: self["canonical_json"],
        compound_marker_builder: self["compound_marker_builder"]
      )
    end

    register("decisions.partition_builder", memoize: true) do
      Write::Decisions::DecisionPartitionBuilder.new
    end

    register("domain.decisions.activation_eligibility", memoize: true) do
      Write::Domain::Decisions::ActivationEligibility.new(
        topic_registry: self["interpretations.topic_registry"]
      )
    end

    register("domain.decisions.prepare_activation", memoize: true) do
      Write::Domain::Decisions::PrepareActivation.new(
        eligibility: self["domain.decisions.activation_eligibility"],
        definition_builder: self["decisions.definition_builder"],
        slot_builder: self["decisions.slot_builder"],
        partition_builder: self["decisions.partition_builder"]
      )
    end

    register("domain.decisions.activate", memoize: true) do
      Write::Domain::Decisions::Activate.new(stream_factory: self["stream_factory"])
    end

    register("domain.decisions.correction_eligibility", memoize: true) do
      Write::Domain::Decisions::CorrectionEligibility.new(
        topic_registry: self["interpretations.topic_registry"]
      )
    end

    register("domain.decisions.prepare_correction", memoize: true) do
      Write::Domain::Decisions::PrepareCorrection.new(
        eligibility: self["domain.decisions.correction_eligibility"],
        definition_builder: self["decisions.definition_builder"],
        slot_builder: self["decisions.slot_builder"],
        partition_builder: self["decisions.partition_builder"]
      )
    end

    register("domain.decisions.correct", memoize: true) do
      Write::Domain::Decisions::Correct.new(stream_factory: self["stream_factory"])
    end

    register("decision_contexts.partition_selector", memoize: true) do
      Write::DecisionContexts::PartitionSelector.new
    end

    register("decision_contexts.resolver", memoize: true) do
      Write::DecisionContexts::Resolver.new
    end

    register("decision_contexts.builder", memoize: true) do
      Write::DecisionContexts::Builder.new(canonical_json: self["canonical_json"])
    end

    register("domain.agent_choices.record", memoize: true) do
      Write::Domain::AgentChoices::Record.new(stream_factory: self["stream_factory"])
    end

    register("domain.candidates.submit", memoize: true) do
      Write::Domain::Candidates::Submit.new(stream_factory: self["stream_factory"])
    end

    register("domain.candidates.submit_impact_surface", memoize: true) do
      Write::Domain::Candidates::SubmitImpactSurface.new(stream_factory: self["stream_factory"])
    end

    register("change_set_activation_source_builder", memoize: true) do
      Processes::ChangeSetActivationSourceBuilder.new(schema_registry: self["event_schema_registry"])
    end

    register("lease_expiry_source_builder", memoize: true) do
      Processes::LeaseExpirySourceBuilder.new(
        contract: Processes::Contracts::LeaseExpirySourceEvent.new(
          compound_marker_builder: self["compound_marker_builder"]
        ),
        schema_registry: self["event_schema_registry"]
      )
    end

    register("lease_expiry_command_builder", memoize: true) do
      Processes::LeaseExpiryCommandBuilder.new
    end

    register("readiness_command_builder", memoize: true) do
      Processes::ReadinessCommandBuilder.new(compound_marker_builder: self["compound_marker_builder"])
    end

    register("readiness_targets_builder", memoize: true) { Processes::ReadinessTargetsBuilder.new }

    register("event_store", memoize: true) do
      Write::EventStore.new(client: PgEventstore.client)
    end

    register("lease_expiry_source_loader", memoize: true) do
      Processes::LeaseExpirySourceLoader.new(
        event_store: self["event_store"],
        source_builder: self["lease_expiry_source_builder"],
        stream_factory: self["stream_factory"]
      )
    end

    register("lease_expiry_job_scheduler", memoize: true) do
      Processes::LeaseExpiryJobScheduler.new(policy: self["lease_expiry_policy"])
    end

    register("tasks.loader", memoize: true) do
      Write::Tasks::Loader.new(
        event_store: self["event_store"],
        stream_factory: self["stream_factory"],
        schema_registry: self["event_schema_registry"]
      )
    end

    register("tasks.target_command_builder", memoize: true) do
      Write::Tasks::TargetCommandBuilder.new
    end

    register("tasks.tool_result_mapper", memoize: true) do
      Write::Tasks::ToolResultMapper.new
    end

    register("repositories.processed_projection_events", memoize: true) do
      Read::Repositories::ProcessedProjectionEvents.new
    end

    register("repositories.command_receipts", memoize: true) do
      Read::Repositories::CommandReceipts.new(schema_registry: self["event_schema_registry"])
    end

    register("repositories.coord_contexts", memoize: true) do
      Read::Repositories::CoordContexts.new
    end

    register("repositories.user_utterances", memoize: true) do
      Read::Repositories::UserUtterances.new
    end

    register("repositories.decision_interpretations", memoize: true) do
      Read::Repositories::DecisionInterpretations.new
    end

    register("repositories.decision_governance", memoize: true) do
      Read::Repositories::DecisionGovernance.new
    end

    register("repositories.agent_choices", memoize: true) do
      Read::Repositories::AgentChoices.new
    end

    register("repositories.agent_choice_impacts", memoize: true) do
      Read::Repositories::AgentChoiceImpacts.new
    end

    register("repositories.candidates", memoize: true) do
      Read::Repositories::Candidates.new
    end

    register("repositories.candidate_impacts", memoize: true) do
      Read::Repositories::CandidateImpacts.new(candidates: self["repositories.candidates"])
    end

    register("projectors.coord_context_v1", memoize: true) do
      Read::Projectors::CoordContextV1.new(
        schema_registry: self["event_schema_registry"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.command_receipts_v1", memoize: true) do
      Read::Projectors::CommandReceiptsV1.new(
        schema_registry: self["event_schema_registry"],
        receipts: self["repositories.command_receipts"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.user_utterances_v1", memoize: true) do
      Read::Projectors::UserUtterancesV1.new(
        schema_registry: self["event_schema_registry"],
        utterances: self["repositories.user_utterances"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.decision_interpretations_v1", memoize: true) do
      Read::Projectors::DecisionInterpretationsV1.new(
        schema_registry: self["event_schema_registry"],
        interpretations: self["repositories.decision_interpretations"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.decision_governance_v1", memoize: true) do
      Read::Projectors::DecisionGovernanceV1.new(
        schema_registry: self["event_schema_registry"],
        governance: self["repositories.decision_governance"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.agent_choices_v1", memoize: true) do
      Read::Projectors::AgentChoicesV1.new(
        schema_registry: self["event_schema_registry"],
        choices: self["repositories.agent_choices"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.agent_choice_impacts_v1", memoize: true) do
      Read::Projectors::AgentChoiceImpactsV1.new(
        schema_registry: self["event_schema_registry"],
        impacts: self["repositories.agent_choice_impacts"],
        choices: self["repositories.agent_choices"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("projectors.candidates_v1", memoize: true) do
      Read::Projectors::CandidatesV1.new(
        schema_registry: self["event_schema_registry"],
        candidates: self["repositories.candidates"],
        candidate_impacts: self["repositories.candidate_impacts"],
        processed_events: self["repositories.processed_projection_events"]
      )
    end

    register("command_completion_lookup", memoize: true) do
      Read::CommandCompletionLookup.new(
        receipts: self["repositories.command_receipts"]
      )
    end

    register("queries.operation_get") do
      Read::Queries::OperationGet.new(
        completions: self["command_completion_lookup"]
      )
    end

    register("queries.coord_context") do
      Read::Queries::CoordContext.new(
        contexts: self["repositories.coord_contexts"],
        canonical_json: self["canonical_json"]
      )
    end

    register("queries.guidance_get") do
      Read::Queries::GuidanceGet.new(
        utterances: self["repositories.user_utterances"]
      )
    end

    register("queries.decision_interpretation_list") do
      Read::Queries::DecisionInterpretationList.new(
        interpretations: self["repositories.decision_interpretations"]
      )
    end

    register("queries.decision_get") do
      Read::Queries::DecisionGet.new(
        governance: self["repositories.decision_governance"]
      )
    end

    register("queries.decision_resolve") do
      Read::Queries::DecisionResolve.new(
        governance: self["repositories.decision_governance"],
        canonical_json: self["canonical_json"],
        clock: self["clock"]
      )
    end

    register("queries.agent_choice_get") do
      Read::Queries::AgentChoiceGet.new(
        choices: self["repositories.agent_choices"]
      )
    end

    register("queries.agent_choice_impact_list") do
      Read::Queries::AgentChoiceImpactList.new(
        impacts: self["repositories.agent_choice_impacts"]
      )
    end

    register("queries.candidate_get") do
      Read::Queries::CandidateGet.new(candidates: self["repositories.candidates"])
    end

    register("queries.candidate_list") do
      Read::Queries::CandidateList.new(candidates: self["repositories.candidates"])
    end

    register("queries.candidate_impact_get") do
      Read::Queries::CandidateImpactGet.new(impacts: self["repositories.candidate_impacts"])
    end

    register("mcp.settings", memoize: true) { Mcp::SettingsLoader.new.call }
    register("mcp.tasks.result_mapper", memoize: true) { Mcp::Tasks::ResultMapper.new }
    register("mcp.tasks.extension", memoize: true) do
      Mcp::Tasks::Extension.new(
        get_task: self["operations.get_coordination_task"],
        acknowledge_task_input: self["operations.acknowledge_task_input"],
        cancel_task: self["operations.cancel_coordination_task"],
        result_mapper: self["mcp.tasks.result_mapper"]
      )
    end
    register("mcp.server", memoize: true) do
      Mcp::ServerFactory.new(tasks_extension: self["mcp.tasks.extension"]).call
    end
    register("mcp.transport", memoize: true) do
      Mcp::TransportFactory.new.call(
        server: self["mcp.server"],
        settings: self["mcp.settings"]
      )
    end

    register("operations.execute_create_change_set") do
      Write::Operations::ExecuteCreateChangeSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_create_change_set"],
        decider: self["domain.change_sets.create"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end


    register("operations.execute_create_work_item") do
      Write::Operations::ExecuteCreateWorkItem.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_create_work_item"],
        decider: self["domain.work_items.create"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end


    register("operations.execute_declare_work_item_dependency") do
      Write::Operations::ExecuteDeclareWorkItemDependency.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_declare_work_item_dependency"],
        decider: self["domain.change_sets.declare_work_item_dependency"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_activate_change_set") do
      Write::Operations::ExecuteActivateChangeSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_activate_change_set"],
        decider: self["domain.change_sets.activate"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_evaluate_work_item_readiness") do
      Write::Operations::ExecuteEvaluateWorkItemReadiness.new(
        event_store: self["event_store"],
        decider: self["domain.work_items.evaluate_readiness"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_acquire_work_item") do
      Write::Operations::ExecuteAcquireWorkItem.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_acquire_work_item"],
        decider: self["domain.work_items.acquire"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_reserve_write_set") do
      Write::Operations::ExecuteReserveWriteSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_reserve_write_set"],
        decider: self["domain.resource_leases.reserve"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"],
        compound_marker_builder: self["compound_marker_builder"]
      )
    end

    register("operations.execute_expand_write_set") do
      Write::Operations::ExecuteExpandWriteSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_expand_write_set"],
        decider: self["domain.resource_leases.expand"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"],
        compound_marker_builder: self["compound_marker_builder"]
      )
    end

    register("operations.execute_renew_lease_set") do
      Write::Operations::ExecuteRenewLeaseSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_renew_lease_set"],
        decider: self["domain.resource_leases.renew"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"],
        compound_marker_builder: self["compound_marker_builder"]
      )
    end

    register("operations.execute_release_lease_set") do
      Write::Operations::ExecuteReleaseLeaseSet.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_release_lease_set"],
        decider: self["domain.resource_leases.release"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"],
        compound_marker_builder: self["compound_marker_builder"]
      )
    end

    register("operations.execute_expire_resource_lease") do
      Write::Operations::ExecuteExpireResourceLease.new(
        event_store: self["event_store"],
        decider: self["domain.resource_leases.expire"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"],
        compound_marker_builder: self["compound_marker_builder"]
      )
    end

    register("operations.execute_record_guidance") do
      Write::Operations::ExecuteRecordGuidance.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_record_guidance"],
        decider: self["domain.guidance.record"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_propose_decision_interpretation") do
      Write::Operations::ExecuteProposeDecisionInterpretation.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_propose_decision_interpretation"],
        decider: self["domain.interpretations.propose"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_adjudicate_decision_interpretation") do
      Write::Operations::ExecuteAdjudicateDecisionInterpretation.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_adjudicate_decision_interpretation"],
        decider: self["domain.interpretations.adjudicate"],
        slot_builder: self["interpretations.slot_builder"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_activate_decision") do
      Write::Operations::ExecuteActivateDecision.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_activate_decision"],
        candidate_preparer: self["domain.decisions.prepare_activation"],
        decider: self["domain.decisions.activate"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_correct_decision") do
      Write::Operations::ExecuteCorrectDecision.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_correct_decision"],
        candidate_preparer: self["domain.decisions.prepare_correction"],
        decider: self["domain.decisions.correct"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_record_agent_choice") do
      Write::Operations::ExecuteRecordAgentChoice.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_record_agent_choice"],
        partition_selector: self["decision_contexts.partition_selector"],
        resolver: self["decision_contexts.resolver"],
        context_builder: self["decision_contexts.builder"],
        decider: self["domain.agent_choices.record"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_submit_candidate") do
      Write::Operations::ExecuteSubmitCandidate.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_submit_candidate"],
        decider: self["domain.candidates.submit"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_submit_candidate_impact_surface") do
      Write::Operations::ExecuteSubmitCandidateImpactSurface.new(
        event_store: self["event_store"],
        preparer: self["operations.prepare_submit_candidate_impact_surface"],
        decider: self["domain.candidates.submit_impact_surface"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"],
        completion_builder: self["command_completion_builder"]
      )
    end

    register("operations.execute_start_agent_choice_impact_scan", memoize: true) do
      Write::Operations::ExecuteStartAgentChoiceImpactScan.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_progress_agent_choice_impact_scan", memoize: true) do
      Write::Operations::ExecuteProgressAgentChoiceImpactScan.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.execute_assess_agent_choice_decision_impact", memoize: true) do
      Write::Operations::ExecuteAssessAgentChoiceDecisionImpact.new(
        event_store: self["event_store"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("lease_expiry_policy", memoize: true) do
      Processes::LeaseExpiryPolicy.new(
        source_loader: self["lease_expiry_source_loader"],
        command_builder: self["lease_expiry_command_builder"],
        operation: self["operations.execute_expire_resource_lease"]
      )
    end

    register("tasks.target_executor", memoize: true) do
      Write::Tasks::TargetExecutor.new(
        event_store: self["event_store"],
        create_change_set: self["operations.execute_create_change_set"],
        create_work_item: self["operations.execute_create_work_item"],
        declare_work_item_dependency: self["operations.execute_declare_work_item_dependency"],
        activate_change_set: self["operations.execute_activate_change_set"],
        acquire_work_item: self["operations.execute_acquire_work_item"],
        reserve_write_set: self["operations.execute_reserve_write_set"],
        expand_write_set: self["operations.execute_expand_write_set"],
        renew_lease_set: self["operations.execute_renew_lease_set"],
        release_lease_set: self["operations.execute_release_lease_set"],
        record_guidance: self["operations.execute_record_guidance"],
        propose_decision_interpretation: self["operations.execute_propose_decision_interpretation"],
        adjudicate_decision_interpretation: self["operations.execute_adjudicate_decision_interpretation"],
        activate_decision: self["operations.execute_activate_decision"],
        correct_decision: self["operations.execute_correct_decision"],
        record_agent_choice: self["operations.execute_record_agent_choice"],
        submit_candidate: self["operations.execute_submit_candidate"],
        submit_candidate_impact_surface:
          self["operations.execute_submit_candidate_impact_surface"]
      )
    end

    register("operations.apply_coordination_task_transition", memoize: true) do
      Write::Operations::ApplyCoordinationTaskTransition.new(
        event_store: self["event_store"],
        loader: self["tasks.loader"],
        stream_factory: self["stream_factory"],
        event_factory: self["event_factory"],
        id_generator: self["id_generator"]
      )
    end

    register("operations.submit_coordination_task") do
      Write::Operations::SubmitCoordinationTask.new(
        event_store: self["event_store"],
        input_digest: self["command_input_digest"],
        clock: self["clock"],
        id_generator: self["id_generator"],
        event_factory: self["event_factory"],
        stream_factory: self["stream_factory"]
      )
    end

    register("operations.submit_create_change_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_create_change_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_create_work_item_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_create_work_item"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_declare_work_item_dependency_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_declare_work_item_dependency"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_activate_change_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_activate_change_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_acquire_work_item_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_acquire_work_item"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_reserve_write_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_reserve_write_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_expand_write_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_expand_write_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_renew_lease_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_renew_lease_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_release_lease_set_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_release_lease_set"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_record_guidance_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_record_guidance"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_propose_decision_interpretation_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_propose_decision_interpretation"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_adjudicate_decision_interpretation_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_adjudicate_decision_interpretation"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_activate_decision_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_activate_decision"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_correct_decision_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_correct_decision"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_record_agent_choice_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_record_agent_choice"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_candidate_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_submit_candidate"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.submit_candidate_impact_surface_task") do
      Write::Operations::PrepareAndSubmitCoordinationTask.new(
        preparer: self["operations.prepare_submit_candidate_impact_surface"],
        submitter: self["operations.submit_coordination_task"]
      )
    end

    register("operations.start_coordination_task", memoize: true) do
      Write::Operations::StartCoordinationTask.new(
        transition: self["operations.apply_coordination_task_transition"],
        clock: self["clock"]
      )
    end

    register("operations.record_coordination_task_outcome", memoize: true) do
      Write::Operations::RecordCoordinationTaskOutcome.new(
        transition: self["operations.apply_coordination_task_transition"],
        clock: self["clock"]
      )
    end

    register("operations.cancel_coordination_task") do
      Write::Operations::CancelCoordinationTask.new(
        transition: self["operations.apply_coordination_task_transition"],
        clock: self["clock"]
      )
    end

    register("operations.get_coordination_task") do
      Write::Operations::GetCoordinationTask.new(loader: self["tasks.loader"])
    end

    register("operations.acknowledge_task_input") do
      Write::Operations::AcknowledgeTaskInput.new(loader: self["tasks.loader"])
    end

    register("coordination_task_source_builder", memoize: true) do
      Processes::CoordinationTaskSourceBuilder.new(
        schema_registry: self["event_schema_registry"]
      )
    end


    register("process_managers.change_set_readiness", memoize: true) do
      Processes::ProcessManagers::ChangeSetReadiness.new(
        event_store: self["event_store"],
        source_builder: self["change_set_activation_source_builder"],
        targets_builder: self["readiness_targets_builder"],
        command_builder: self["readiness_command_builder"],
        operation: self["operations.execute_evaluate_work_item_readiness"],
        schema_registry: self["event_schema_registry"],
        stream_factory: self["stream_factory"]
      )
    end

    register("process_managers.coordination_task_executor", memoize: true) do
      Processes::ProcessManagers::CoordinationTaskExecutor.new(
        event_store: self["event_store"],
        source_builder: self["coordination_task_source_builder"],
        task_loader: self["tasks.loader"],
        transition: self["operations.apply_coordination_task_transition"],
        start_task: self["operations.start_coordination_task"],
        record_outcome: self["operations.record_coordination_task_outcome"],
        target_command_builder: self["tasks.target_command_builder"],
        target_executor: self["tasks.target_executor"],
        tool_result_mapper: self["tasks.tool_result_mapper"],
        stream_factory: self["stream_factory"]
      )
    end

    register("process_managers.lease_expiry_scheduler", memoize: true) do
      Processes::ProcessManagers::LeaseExpiryScheduler.new(
        source_builder: self["lease_expiry_source_builder"],
        job_scheduler: self["lease_expiry_job_scheduler"]
      )
    end

    register("process_managers.agent_choice_decision_impact", memoize: true) do
      Processes::ProcessManagers::AgentChoiceDecisionImpact.new(
        event_store: self["event_store"],
        start_scan: self["operations.execute_start_agent_choice_impact_scan"],
        progress_scan: self["operations.execute_progress_agent_choice_impact_scan"],
        assess_impact: self["operations.execute_assess_agent_choice_decision_impact"]
      )
    end

    register("subscriptions.change_set_readiness", memoize: true) do
      Processes::Subscriptions::ChangeSetReadiness.new(handler: self["process_managers.change_set_readiness"])
    end

    register("subscriptions.coordination_task_executor", memoize: true) do
      Processes::Subscriptions::CoordinationTaskExecutor.new(
        handler: self["process_managers.coordination_task_executor"]
      )
    end

    register("subscriptions.lease_expiry_scheduler", memoize: true) do
      Processes::Subscriptions::LeaseExpiryScheduler.new(
        handler: self["process_managers.lease_expiry_scheduler"]
      )
    end

    register("subscriptions.agent_choice_decision_impact", memoize: true) do
      Processes::Subscriptions::AgentChoiceDecisionImpact.new(
        handler: self["process_managers.agent_choice_decision_impact"]
      )
    end

    register("subscriptions.coord_context", memoize: true) do
      Read::Subscriptions::CoordContext.new(handler: self["projectors.coord_context_v1"])
    end

    register("subscriptions.command_receipts", memoize: true) do
      Read::Subscriptions::CommandReceipts.new(handler: self["projectors.command_receipts_v1"])
    end

    register("subscriptions.user_utterances", memoize: true) do
      Read::Subscriptions::UserUtterances.new(handler: self["projectors.user_utterances_v1"])
    end

    register("subscriptions.decision_interpretations", memoize: true) do
      Read::Subscriptions::DecisionInterpretations.new(
        handler: self["projectors.decision_interpretations_v1"]
      )
    end

    register("subscriptions.decision_governance", memoize: true) do
      Read::Subscriptions::DecisionGovernance.new(
        handler: self["projectors.decision_governance_v1"]
      )
    end

    register("subscriptions.agent_choices", memoize: true) do
      Read::Subscriptions::AgentChoices.new(
        handler: self["projectors.agent_choices_v1"]
      )
    end

    register("subscriptions.agent_choice_impacts", memoize: true) do
      Read::Subscriptions::AgentChoiceImpacts.new(
        handler: self["projectors.agent_choice_impacts_v1"]
      )
    end

    register("subscriptions.candidates", memoize: true) do
      Read::Subscriptions::Candidates.new(handler: self["projectors.candidates_v1"])
    end

    register("subscription_managers.process_managers", memoize: true) do
      PgEventstore.subscriptions_manager(
        subscription_set: Processes::Subscriptions::ProcessManagerSet::SET_NAME
      )
    end

    register("subscription_sets.process_managers", memoize: true) do
      Processes::Subscriptions::ProcessManagerSet.new(
        manager: self["subscription_managers.process_managers"],
        registrations: [
          self["subscriptions.change_set_readiness"],
          self["subscriptions.coordination_task_executor"],
          self["subscriptions.lease_expiry_scheduler"],
          self["subscriptions.agent_choice_decision_impact"]
        ]
      )
    end


    register("subscription_managers.read_models", memoize: true) do
      PgEventstore.subscriptions_manager(
        subscription_set: Read::Subscriptions::ReadModelSet::SET_NAME
      )
    end

    register("subscription_sets.read_models", memoize: true) do
      Read::Subscriptions::ReadModelSet.new(
        manager: self["subscription_managers.read_models"],
        registrations: [
          self["subscriptions.coord_context"],
          self["subscriptions.command_receipts"],
          self["subscriptions.user_utterances"],
          self["subscriptions.decision_governance"],
          self["subscriptions.decision_interpretations"],
          self["subscriptions.agent_choices"],
          self["subscriptions.agent_choice_impacts"],
          self["subscriptions.candidates"]
        ]
      )
    end
  end

  Import = Dry::AutoInject(Container)
end
