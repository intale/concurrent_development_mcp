# frozen_string_literal: true

module McpAcceptanceWorld
  PROTOCOL_VERSION = "2026-07-28"
  TASKS_EXTENSION = "io.modelcontextprotocol/tasks"
  IMPACT_POLICY_VERSION = "agent-choice-decision-impact/v1"

  def tasks_capable=(value)
    @tasks_capable = value
  end

  def tasks_capable?
    @tasks_capable != false
  end

  def call_tool(name, arguments, expected_status: 200, client_id: "default")
    mcp_request(
      method: "tools/call",
      params: { name:, arguments: },
      name:,
      expected_status:,
      client_id:
    )
  end

  def task_request(method, task_id, params = {}, client_id: "default")
    mcp_request(
      method:,
      params: params.merge(taskId: task_id),
      name: task_id,
      client_id:
    )
  end

  def mcp_request(method:, params:, name: nil, expected_status: 200, client_id: "default")
    session = mcp_session(client_id)
    session.post(
      "/mcp",
      params: JSON.generate(
        jsonrpc: "2.0",
        id: next_request_id(client_id),
        method:,
        params: modern_params(params, client_id:)
      ),
      headers: request_headers(method:, name:)
    )
    assert_acceptance(
      session.response.status == expected_status,
      "Expected HTTP #{expected_status}, got #{session.response.status}: #{session.response.body}"
    )
    JSON.parse(session.response.body)
  end

  def execute_task(task_id)
    start_process_subscriptions
    await_task_terminal(task_id)
  end

  def submit_and_execute(tool, client_id: "default", **arguments)
    response = call_tool(tool, arguments, client_id:)
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "#{tool} did not return a Task handle: #{response.inspect}")
    start_process_subscriptions
    await_task_terminal(task_id, client_id:)
    task_id
  end

  def submit_and_await(tool, client_id: "default", **arguments)
    response = call_tool(tool, arguments, client_id:)
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "#{tool} did not return a Task handle: #{response.inspect}")
    start_process_subscriptions
    await_task_terminal(task_id, client_id:)
    task_id
  end

  def resource_target(
    kind:,
    path:,
    repository_id: acceptance_repository_id,
    base_blob_oid: nil,
    client_id: "default",
    actor_id: nil
  )
    resource_id = resolve_resource_id(
      kind:,
      path:,
      repository_id:,
      client_id:,
      actor_id:
    )
    { resource_id:, base_blob_oid: }.compact
  end

  def resolve_resource_id(
    kind:,
    path:,
    repository_id: acceptance_repository_id,
    client_id: "default",
    actor_id: nil
  )
    @acceptance_resource_ids ||= {}
    key = [ repository_id, kind, path ]
    return @acceptance_resource_ids.fetch(key) if @acceptance_resource_ids.key?(key)

    @resource_resolution_sequence = @resource_resolution_sequence.to_i + 1
    task_id = submit_and_execute(
      "resource_resolve",
      client_id:,
      command_id: "cuc-resource-resolve-#{@resource_resolution_sequence}",
      actor: { kind: "agent", id: actor_id || (client_id == "default" ? "resource-agent" : client_id) },
      repository_id:,
      kind:,
      path:
    )
    state = task_request("tasks/get", task_id, client_id:)
    result = state.dig("result", "result")
    assert_acceptance_equal("completed", state.dig("result", "status"), "Resource resolution Task")
    assert_acceptance_equal(false, result&.fetch("isError"), "Resource resolution error")
    resource_id = result.dig("structuredContent", "data", "resource_id")
    assert_acceptance(
      Coordinator::Shared::Types::UUID_V7_PATTERN.match?(resource_id.to_s),
      "Resource resolution returned no UUIDv7: #{result.inspect}"
    )
    @acceptance_resource_ids[key] = resource_id
  end

  def prepare_mcp_clients(*client_ids)
    client_ids.each { mcp_session(_1) }
  end

  def submit_tasks_in_distinct_execution_lanes(client_ids:, maximum_rounds: 8)
    stop_process_subscriptions
    candidates = []
    selected = nil

    maximum_rounds.times do |round|
      client_ids.each do |client_id|
        candidate = yield(client_id, round)
        task_id = candidate.fetch(:task_id)
        candidates << candidate.merge(
          client_id:,
          worker_lane: Coordinator::Write::Tasks::ExecutionLane.new.index(task_id)
        )
      end
      selected = candidates.combination(2).find do |left, right|
        left.fetch(:client_id) != right.fetch(:client_id) &&
          left.fetch(:worker_lane) != right.fetch(:worker_lane)
      end
      break if selected
    end

    assert_acceptance(selected, "Could not allocate Tasks in distinct execution lanes")
    selected_task_ids = selected.map { _1.fetch(:task_id) }.to_set
    candidates.reject { selected_task_ids.include?(_1.fetch(:task_id)) }.each do |candidate|
      task_request("tasks/cancel", candidate.fetch(:task_id), client_id: candidate.fetch(:client_id))
    end
    selected.sort_by { _1.fetch(:worker_lane) }
  end

  def project_change_set(change_set_id)
    await_read_model("ChangeSet #{change_set_id} to become available") do
      payload = coordination_context(change_set_id:)
      [ payload.dig("data", "context", "change_set", "change_set_id") == change_set_id, payload ]
    end
  end

  def project_attempt_context(change_set_id:, work_item_id:, attempt_id:)
    expected_lease_set_id = write_set_events(attempt_id).last&.data&.fetch("lease_set_id", nil)
    await_read_model("Attempt #{attempt_id} coordination context to become available") do
      payload = coordination_context(attempt_id:)
      context = payload.dig("data", "context")
      attempt = context&.fetch("attempts", [])&.find { _1.fetch("attempt_id") == attempt_id }
      matches = context&.dig("change_set", "change_set_id") == change_set_id &&
                context.fetch("work_items", []).any? { _1.fetch("work_item_id") == work_item_id } &&
                attempt &&
                (!expected_lease_set_id || attempt.dig("write_set", "lease_set_id") == expected_lease_set_id)
      [ matches, payload ]
    end
  end

  def await_work_item_ready(work_item_id)
    start_process_subscriptions
    eventually("WorkItem #{work_item_id} to become ready") do
      events = work_item_events(work_item_id)
      [ events.any? { _1.type == "WorkItemMadeReady" }, events.map(&:type) ]
    end
  end

  def task_events(task_id)
    event_store.read(
      streams.coordination_task(task_id),
      Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY
    )
  end

  def task_events_for_command(command_id)
    PgEventstore.client.read(
      PgEventstore::Stream.all_stream,
      options: {
        direction: :asc,
        max_count: 1,
        filter: {
          event_types: [
            {
              type: "CoordinationTaskSubmitted",
              markers: [ "command:#{command_id}" ]
            }
          ]
        }
      }
    )
  end

  def command_events(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    )
  end

  def change_set_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end

  def work_item_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventQueries::WORK_ITEM_FOR_ACQUISITION
    )
  end

  def attempt_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventQueries::ATTEMPT_FOR_WRITE_SET_EXPANSION
    )
  end

  def write_set_events(attempt_id)
    attempt_events(attempt_id).select { _1.type == "WriteSetReserved" }
  end

  def write_set_expansion_events(attempt_id)
    attempt_events(attempt_id).select { _1.type == "WriteSetExpanded" }
  end

  def write_set_renewal_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "WriteSetRenewed" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def write_set_release_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "WriteSetReleased" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def guidance_events(conversation_id)
    event_store.read(
      streams.conversation(conversation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::EventQueries::GUIDANCE_MESSAGE_EVENT_TYPES,
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def project_guidance(conversation_id)
    message_id = guidance_events(conversation_id).last&.data&.fetch("message_id", nil)
    assert_acceptance(message_id, "Conversation #{conversation_id} has no guidance fact")
    await_read_model("Guidance #{message_id} to become available") do
      payload = call_tool("guidance_get", { message_id: }).dig("result", "structuredContent")
      [ payload.dig("data", "guidance", "message_id") == message_id, payload ]
    end
  end

  def interpretation_events(message_id)
    event_store.read(
      streams.interpretation(message_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          DecisionInterpretationProposed
          DecisionClarificationRequired
          DecisionInterpretationAccepted
          DecisionInterpretationRejected
        ],
        maximum_count: 100,
        direction: :asc
      )
    )
  end

  def project_interpretations(message_id)
    expected = interpretation_events(message_id).each_with_object({}) do |event, statuses|
      statuses[event.data.fetch("interpretation_id")] = {
        "DecisionInterpretationProposed" => "proposed",
        "DecisionClarificationRequired" => "clarification_required",
        "DecisionInterpretationAccepted" => "accepted",
        "DecisionInterpretationRejected" => "rejected"
      }.fetch(event.type)
    end
    await_read_model("Interpretations for #{message_id} to converge") do
      observed = interpretation_page(message_id).to_h do |item|
        [ item.fetch("interpretation_id"), item.fetch("lifecycle_status") ]
      end
      [ expected.all? { |id, status| observed[id] == status }, observed ]
    end
  end

  def interpretation_page(message_id)
    call_tool(
      "decision_interpretation_list",
      { message_id:, after_revision: -1, limit: 20 }
    ).dig("result", "structuredContent", "data", "page", "interpretations")
  end

  def interpretation_adjudication_arguments(command_id:, interpretation_id:, action:, clarification: nil)
    {
      command_id:,
      actor: { kind: "orchestrator", id: "guidance-host" },
      source_message_id: @interpretation_message_id,
      interpretation_id:,
      action:,
      rationale: {
        code: action == "reject" ? "user_rejected" : "user_confirmed",
        summary: action == "reject" ? "The reading is not intended." : "The host assessed the proposed reading."
      },
      clarification:
    }
  end

  def decision_events(decision_id)
    event_store.read(
      streams.decision(decision_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionRecorded DecisionActivated DecisionDefinitionCorrected],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def decision_slot_events(slot_id)
    event_store.read(
      streams.decision_slot(slot_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionSlotOpened DecisionSlotHeadChanged],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def decision_partition_events(partition_id = "repo:#{acceptance_repository_id}:testing")
    event_store.read(
      streams.decision_partition(partition_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "DecisionPartitionAdvanced" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def decision_view(decision_id)
    call_tool("decision_get", { decision_id: })
      .dig("result", "structuredContent")
  end

  def project_decision_recorded(decision_id)
    event = decision_events(decision_id).find { _1.type == "DecisionRecorded" }
    assert_acceptance(event, "Decision #{decision_id} has no DecisionRecorded fact")
    await_read_model("Decision #{decision_id} to become available") do
      payload = decision_view(decision_id)
      [ payload.dig("data", "decision", "decision_id") == decision_id, payload ]
    end
  end

  def project_remaining_decision_facts(decision_id)
    activated = decision_events(decision_id).find { _1.type == "DecisionActivated" }
    assert_acceptance(activated, "Decision #{decision_id} is not activated")
    await_read_model("Decision #{decision_id} to become active") do
      payload = decision_view(decision_id)
      [ payload.dig("data", "decision", "policy_status") == "active", payload ]
    end
  end

  def await_effective_decision_context(decision_id, context:)
    await_read_model("Decision #{decision_id} to resolve from its active partition") do
      payload = call_tool(
        "decision_resolve",
        { topic_id: "testing.framework", context: }
      ).dig("result", "structuredContent")
      decision_context = payload.dig("data", "decision_context")
      observed_decision_id = decision_context&.dig(
        "document", "effective_decision", "head", "decision_id"
      )
      [ payload["status"] == "ok" && observed_decision_id == decision_id, decision_context ]
    end
  end

  def project_decision_correction(decision_id)
    event = decision_events(decision_id).find { _1.type == "DecisionDefinitionCorrected" }
    assert_acceptance(event, "Decision #{decision_id} has no DecisionDefinitionCorrected fact")
    await_read_model("Decision #{decision_id} correction to become available") do
      payload = decision_view(decision_id)
      observed = payload.dig("data", "decision", "current_head", "event", "event_id")
      [ observed == event.id, payload ]
    end
  end

  def agent_choice_events(choice_id)
    event_store.read(
      streams.agent_choice(choice_id),
      Coordinator::Write::EventQueries::AGENT_CHOICE_EXISTENCE
    )
  end

  def agent_choice_view(choice_id)
    call_tool("agent_choice_get", { choice_id: })
      .dig("result", "structuredContent")
  end

  def project_agent_choice_event(choice_id, event_type)
    event = agent_choice_events(choice_id).find { _1.type == event_type }
    assert_acceptance(event, "AgentChoice #{choice_id} has no #{event_type} fact")
    expected_status = event_type == "AgentChoiceRecorded" ? %w[recorded accepted invalidated] : %w[accepted invalidated]
    await_read_model("AgentChoice #{choice_id} to expose #{event_type}") do
      payload = agent_choice_view(choice_id)
      [ expected_status.include?(payload.dig("data", "choice", "observation_status")), payload ]
    end
  end

  def record_testing_framework_choice(choice_id:, option_id:)
    command_id = "cmd-cuc-choice-record-#{choice_id}"
    task_id = submit_and_execute(
      "agent_choice_record",
      command_id:,
      actor: { kind: "agent", id: @choice_agent_id },
      choice_id:,
      choice_type: "testing.framework",
      selected: { option_id:, summary: choice_option_summary(option_id) },
      alternatives: [ alternative_choice(option_id) ],
      reason_summary: "Use the framework that fits the available coordination policy.",
      context: @choice_context,
      decision_context: @choice_decision_context
    )
    {
      choice_id:,
      command_id:,
      task_id:,
      state: task_request("tasks/get", task_id)
    }
  end

  def accept_impact_interpretation(decision_id:, option_id:, correction:, advisory:)
    suffix = correction ? "#{decision_id}-correction" : "#{decision_id}-activation"
    message_id = "M-CUC-#{suffix}"
    interpretation_id = "I-CUC-#{suffix}"
    tasks = []
    tasks << submit_and_execute(
      "guidance_record",
      command_id: "cmd-cuc-impact-guidance-#{suffix}",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-CUC-#{suffix}",
      source: "mcp_client",
      text: "Use #{option_id}.",
      anchors: {
        repository_ids: [ acceptance_repository_id ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    )
    tasks << submit_and_execute(
      "decision_interpretation_propose",
      **impact_interpretation_arguments(
        suffix:,
        message_id:,
        interpretation_id:,
        decision_id:,
        option_id:,
        correction:,
        advisory:
      )
    )
    tasks << submit_and_execute(
      "decision_interpretation_adjudicate",
      command_id: "cmd-cuc-impact-adjudication-#{suffix}",
      actor: { kind: "orchestrator", id: "guidance-host" },
      source_message_id: message_id,
      interpretation_id:,
      action: "accept",
      rationale: {
        code: "user_confirmed",
        summary: "The impact policy matches the intended guidance."
      },
      clarification: nil
    )
    tasks.each { assert_successful_task(_1, "Impact interpretation setup") }
    { interpretation_id:, message_id: }
  end

  def activate_impact_decision(decision_id:, option_id:, available:)
    candidate = accept_impact_interpretation(
      decision_id:,
      option_id:,
      correction: false,
      advisory: false
    )
    task_id = submit_and_execute(
      "decision_activate",
      command_id: "cmd-cuc-impact-activate-#{decision_id}",
      actor: { kind: "orchestrator", id: "guidance-host" },
      decision_id:,
      interpretation_id: candidate.fetch(:interpretation_id),
      rationale: { code: "user_confirmed", summary: "Activate the accepted impact policy." }
    )
    assert_successful_task(task_id, "Impact Decision activation")
    source = decision_events(decision_id).find { _1.type == "DecisionActivated" }
    assert_acceptance(source, "Decision #{decision_id} has no activation source")
    if available
      project_decision_recorded(decision_id)
      project_remaining_decision_facts(decision_id)
      await_effective_decision_context(decision_id, context: @choice_context)
    end
    source
  end

  def correct_impact_decision(decision_id:, option_id:)
    candidate = accept_impact_interpretation(
      decision_id:,
      option_id:,
      correction: true,
      advisory: true
    )
    expected_head = decision_view(decision_id).dig("data", "decision", "current_head", "event")
    assert_acceptance(expected_head, "Decision #{decision_id} has no available correction head")
    task_id = submit_and_execute(
      "decision_correct",
      command_id: "cmd-cuc-impact-correct-#{decision_id}",
      actor: { kind: "orchestrator", id: "guidance-host" },
      decision_id:,
      interpretation_id: candidate.fetch(:interpretation_id),
      expected_head:,
      rationale: {
        code: "normalization_corrected",
        summary: "Apply the compatible active-attempt correction."
      }
    )
    assert_successful_task(task_id, "Impact Decision correction")
    source = decision_events(decision_id).find { _1.type == "DecisionDefinitionCorrected" }
    assert_acceptance(source, "Decision #{decision_id} has no correction source")
    source
  end

  def drive_impact_saga(source)
    start_process_subscriptions
    events = eventually("Decision change #{source.id} impact Saga to complete") do
      observed = impact_scan_events(source)
      [ observed.any? { _1.type == "AgentChoiceImpactScanCompleted" }, observed ]
    end
    restart_process_subscriptions
    redelivered = eventually("Decision change #{source.id} impact Saga to remain terminal after restart") do
      observed = impact_scan_events(source)
      completed_count = observed.count { _1.type == "AgentChoiceImpactScanCompleted" }
      [ completed_count == 1, observed ]
    end
    started = events.find { _1.type == "AgentChoiceImpactScanStarted" }
    completed = redelivered.find { _1.type == "AgentChoiceImpactScanCompleted" }
    { started:, completed: }
  end

  def impact_scan_events(source)
    started = read_global_marked_events(
      stream_context: "AgentGovernance",
      stream_name: "AgentChoiceImpactScan",
      event_types: [ "AgentChoiceImpactScanStarted" ],
      marker: "decision-change:#{source.id}",
      maximum_count: 1
    ).first
    return [] unless started

    event_store.read_grouped(
      streams.agent_choice_impact_scan(started.stream.stream_id),
      Coordinator::Write::EventQueries::AGENT_CHOICE_IMPACT_SCAN_STATE
    )
  end

  def impact_choice_events(choice_id)
    event_store.read(
      streams.agent_choice(choice_id),
      Coordinator::Write::EventQueries::AGENT_CHOICE_FOR_IMPACT
    )
  end

  def impact_assessment_event(choice_id, source = @impact_source)
    accepted = impact_choice_events(choice_id).find { _1.type == "AgentChoiceAccepted" }
    assert_acceptance(accepted, "AgentChoice #{choice_id} has no accepted source")
    marker = Coordinator::Write::AgentChoiceImpacts::AssessmentMarkerBuilder.new.call(
      accepted_choice: impact_event_reference(accepted),
      decision_change: impact_event_reference(source)
    )
    read_global_marked_events(
      stream_context: "AgentGovernance",
      stream_name: "AgentChoiceImpact",
      event_types: [ "AgentChoiceImpactAssessed" ],
      marker:,
      maximum_count: 1
    ).first
  end

  def read_global_marked_events(stream_context:, stream_name:, event_types:, marker:, maximum_count:)
    event_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context:,
        stream_name:,
        event_types:,
        markers: [ marker ],
        maximum_count:,
        direction: :asc
      )
    )
  end

  def process_step_event(source_event:, process_name:, step_name:, subject_kind:, subject_id:)
    marker = Coordinator::Shared::Markers::CodecV2.new.call(
      purpose: "process-step",
      components: [
        { dimension: "process-name", value: process_name },
        { dimension: "source-event-id", value: source_event.id },
        { dimension: "step-name", value: step_name },
        { dimension: "subject-kind", value: subject_kind },
        { dimension: "subject-id", value: subject_id }
      ]
    ).value!.marker
    read_global_marked_events(
      stream_context: "CoordinatorControl",
      stream_name: "ProcessStep",
      event_types: [ "ProcessStepPlanned" ],
      marker:,
      maximum_count: 1
    ).first
  end

  def impact_payload(event)
    Coordinator::Container["event_schema_registry"].load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def project_impact_assessment(choice_id)
    event = impact_assessment_event(choice_id)
    assert_acceptance(event, "AgentChoice #{choice_id} has no impact assessment")
    attempt_id = impact_payload(event).attempt_id
    await_read_model("AgentChoice #{choice_id} impact assessment to become available") do
      page = impact_page(attempt_id:)
      [ page.fetch("items").any? { _1.fetch("choice_id") == choice_id }, page ]
    end
  end

  def project_choice_invalidation(choice_id)
    event = impact_choice_events(choice_id).find { _1.type == "AgentChoiceInvalidatedByDecision" }
    assert_acceptance(event, "AgentChoice #{choice_id} has no invalidation")
    await_read_model("AgentChoice #{choice_id} invalidation to become available") do
      payload = agent_choice_view(choice_id)
      [ payload.dig("data", "choice", "observation_status") == "invalidated", payload ]
    end
  end

  def impact_page(attempt_id:, after_global_position: nil, limit: 20)
    arguments = { attempt_id:, limit: }
    arguments[:after_global_position] = after_global_position if after_global_position
    call_tool("agent_choice_impact_list", arguments)
      .dig("result", "structuredContent", "data", "page")
  end

  def impact_event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def impact_interpretation_arguments(
    suffix:,
    message_id:,
    interpretation_id:,
    decision_id:,
    option_id:,
    correction:,
    advisory:
  )
    {
      command_id: "cmd-cuc-impact-proposal-#{suffix}",
      actor: { kind: "agent", id: "classifier-impact" },
      interpretation_id:,
      source_message_id: message_id,
      source_span: {
        start_character: 4,
        end_character: 4 + option_id.length,
        text: option_id
      },
      classifier: {
        id: "classifier-impact",
        version: "decision-classifier-v1",
        ontology_version: 1,
        confidence_millionths: 950_000
      },
      proposed_decision: {
        statement_kind: advisory ? "preference" : "directive",
        topic_id: "testing.framework",
        effect: advisory ? "prefer" : "require",
        modality: advisory ? "should" : "must",
        value: {
          schema: "named-choice/v1",
          name: option_id,
          items: nil,
          target_kind: nil,
          target_id: nil,
          action: nil
        },
        scope: impact_repository_scope,
        conditions: {
          phases: [ "implementation" ],
          languages: [ "ruby" ],
          tags: [],
          repository_kinds: [],
          artifact_kinds: [],
          environments: []
        },
        validity: { valid_from: nil, valid_until: nil, until_event: nil },
        authority: { actor_id: "user-label", role: "project-owner" },
        enforcement: {
          level: advisory ? "advisory" : "implementation_gate",
          retroactivity: "active_attempts",
          on_violation: advisory ? "warn" : "block"
        },
        relations: {
          corrects: correction ? [ decision_id ] : [],
          supersedes: [],
          exception_to: [],
          revokes: []
        }
      },
      ambiguities: []
    }
  end

  def impact_repository_scope
    {
      workspace_id: nil,
      repository_ids: [ acceptance_repository_id ],
      branch_selectors: [],
      change_set_id: nil,
      work_item_id: nil,
      attempt_id: nil,
      candidate_id: nil,
      path_selectors: [],
      symbol_selectors: [],
      contract_selectors: [],
      schema_selectors: [],
      environments: [],
      agent_roles: []
    }
  end

  def assert_successful_task(task_id, context)
    state = task_request("tasks/get", task_id)
    assert_acceptance_equal("completed", state.dig("result", "status"), "#{context} status")
    assert_acceptance_equal(false, state.dig("result", "result", "isError"), "#{context} error")
    state
  end

  def choice_option_summary(option_id)
    option_id == "rspec" ? "RSpec" : option_id.capitalize
  end

  def alternative_choice(option_id)
    alternative = option_id == "rspec" ? "minitest" : "rspec"
    { option_id: alternative, summary: choice_option_summary(alternative) }
  end

  def accept_correction_interpretation(decision_id:, interpretation_id:, message_id:, value:, suffix:)
    task_ids = []
    task_ids << submit_and_execute(
      "guidance_record",
      command_id: "cmd-cuc-correction-guidance-#{suffix}",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-CUC-COR-#{suffix}",
      source: "mcp_client",
      text: "Use #{value} as the test framework.",
      anchors: {
        repository_ids: [ acceptance_repository_id ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    )
    task_ids << submit_and_execute(
      "decision_interpretation_propose",
      command_id: "cmd-cuc-correction-proposal-#{suffix}",
      actor: { kind: "agent", id: "classifier-correction-#{suffix}" },
      interpretation_id:,
      source_message_id: message_id,
      source_span: nil,
      classifier: {
        id: "classifier-correction-#{suffix}",
        version: "decision-classifier-v1",
        ontology_version: 1,
        confidence_millionths: 940_000
      },
      proposed_decision: {
        statement_kind: "preference",
        topic_id: "testing.framework",
        effect: "prefer",
        modality: "should",
        value: {
          schema: "named-choice/v1",
          name: value,
          items: nil,
          target_kind: nil,
          target_id: nil,
          action: nil
        },
        scope: nil,
        conditions: {
          phases: [ "implementation" ],
          languages: [ "ruby" ],
          tags: [],
          repository_kinds: [],
          artifact_kinds: [],
          environments: []
        },
        validity: { valid_from: nil, valid_until: nil, until_event: nil },
        authority: { actor_id: "user-label", role: "project-owner" },
        enforcement: {
          level: "advisory",
          retroactivity: "future_only",
          on_violation: "warn"
        },
        relations: {
          corrects: [ decision_id ],
          supersedes: [],
          exception_to: [],
          revokes: []
        }
      },
      ambiguities: []
    )
    task_ids << submit_and_execute(
      "decision_interpretation_adjudicate",
      command_id: "cmd-cuc-correction-adjudication-#{suffix}",
      actor: { kind: "orchestrator", id: "guidance-host" },
      source_message_id: message_id,
      interpretation_id:,
      action: "accept",
      rationale: {
        code: "user_confirmed",
        summary: "The correction matches the intended guidance."
      },
      clarification: nil
    )

    task_ids.each do |task_id|
      state = task_request("tasks/get", task_id)
      assert_acceptance_equal("completed", state.dig("result", "status"), "Correction setup Task status")
      assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Correction setup error")
    end

    {
      decision_id:,
      interpretation_id:,
      message_id:,
      value:,
      command_id: "cmd-cuc-decision-correction-#{suffix}"
    }
  end

  def lease_events(path, kind: "file", repository_id: acceptance_repository_id)
    resource_id = (@acceptance_resource_ids || {}).fetch([ repository_id, kind, path ]) do
      raise "Resource #{repository_id}/#{kind}/#{path} was not resolved through MCP"
    end
    event_store.read(
      streams.resource_lease(resource_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [
          "ResourceLeaseAcquired",
          "ResourceLeaseRenewed",
          "ResourceLeaseReleased",
          "ResourceLeaseExpired"
        ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def work_item_arguments(agent_id:, work_item_id:, change_set_id:, command_id:)
    {
      command_id:,
      actor: { kind: "agent", id: agent_id },
      change_set_id:,
      work_item_id:,
      repository_id: acceptance_repository_id,
      goal: "Implement #{work_item_id}",
      acceptance_criteria: [ "The work is verifiable" ]
    }
  end

  def assert_no_current_coordination_facts
    assert_acceptance_equal([], command_events(@current_arguments.fetch(:command_id)), "Command facts")
    assert_acceptance_equal([], change_set_events(@current_arguments.fetch(:change_set_id)), "ChangeSet facts")
    return unless @current_arguments[:work_item_id]

    assert_acceptance_equal([], work_item_events(@current_arguments.fetch(:work_item_id)), "WorkItem facts")
  end

  def assert_acceptance(condition, message)
    raise message unless condition
  end

  def assert_acceptance_equal(expected, actual, context)
    return if expected == actual

    raise "#{context}: expected #{expected.inspect}, got #{actual.inspect}"
  end

  def coordination_context(**scope)
    call_tool("coord_context", scope).dig("result", "structuredContent")
  end

  private

  def mcp_session(client_id = "default")
    @mcp_sessions_mutex ||= Thread::Mutex.new
    @mcp_sessions_mutex.synchronize do
      @mcp_sessions ||= {}
      @mcp_sessions[client_id] ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
        session.host! "localhost"
      end
    end
  end

  def next_request_id(client_id)
    @request_ids_mutex ||= Thread::Mutex.new
    @request_ids_mutex.synchronize do
      @request_ids ||= {}
      @request_ids[client_id] = @request_ids.fetch(client_id, 0) + 1
    end
  end

  def modern_params(params, client_id:)
    extensions = tasks_capable? ? { TASKS_EXTENSION => {} } : {}
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion": PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities": { extensions: },
        "io.modelcontextprotocol/clientInfo": { name: "cucumber/#{client_id}", version: "1.0" }
      }
    )
  end

  def request_headers(method:, name:)
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream",
      "MCP-Protocol-Version" => PROTOCOL_VERSION,
      "Mcp-Method" => method,
      "Mcp-Name" => name
    }.compact
  end

  def event_store
    @event_store ||= Coordinator::Write::EventStore.new(client: PgEventstore.client)
  end

  def streams
    @streams ||= Coordinator::Write::StreamFactory.new
  end
end

World(McpAcceptanceWorld)
