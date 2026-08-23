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

  def call_tool(name, arguments, expected_status: 200)
    mcp_request(
      method: "tools/call",
      params: { name:, arguments: },
      name:,
      expected_status:
    )
  end

  def task_request(method, task_id, params = {})
    mcp_request(
      method:,
      params: params.merge(taskId: task_id),
      name: task_id
    )
  end

  def mcp_request(method:, params:, name: nil, expected_status: 200)
    mcp_session.post(
      "/mcp",
      params: JSON.generate(
        jsonrpc: "2.0",
        id: next_request_id,
        method:,
        params: modern_params(params)
      ),
      headers: request_headers(method:, name:)
    )
    assert_acceptance(
      mcp_session.response.status == expected_status,
      "Expected HTTP #{expected_status}, got #{mcp_session.response.status}: #{mcp_session.response.body}"
    )
    JSON.parse(mcp_session.response.body)
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    assert_acceptance(submitted, "Task #{task_id} has no persisted submission")
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
  end

  def submit_and_execute(tool, **arguments)
    task_id = call_tool(tool, arguments).dig("result", "taskId")
    assert_acceptance(task_id, "#{tool} did not return a Task handle")
    execute_task(task_id)
    task_id
  end

  def project_change_set(change_set_id)
    projector = Coordinator::Container["projectors.coord_context_v1"]
    change_set_events(change_set_id).each { projector.call(_1) }
  end

  def project_attempt_context(change_set_id:, work_item_id:, attempt_id:)
    projector = Coordinator::Container["projectors.coord_context_v1"]
    planning = change_set_events(change_set_id)
    work = work_item_events(work_item_id)
    planning.first(2).each { projector.call(_1) }
    projector.call(work.first)
    planning.drop(2).each { projector.call(_1) }
    work.drop(1).each { projector.call(_1) }
    attempt_events(attempt_id).each { projector.call(_1) }
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
    projector = Coordinator::Container["projectors.user_utterances_v1"]
    guidance_events(conversation_id).each { projector.call(_1) }
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
    projector = Coordinator::Container["projectors.decision_interpretations_v1"]
    interpretation_events(message_id).each { projector.call(_1) }
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

  def decision_partition_events(partition_id = "repo:billing:testing")
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
    decision_projector.call(event)
  end

  def project_remaining_decision_facts(decision_id)
    recorded, activated = decision_events(decision_id).first(2)
    assert_acceptance(recorded && activated, "Decision #{decision_id} is not completely persisted")
    slot_id = activated.data.fetch("slot").fetch("slot_id")
    [ activated, *decision_slot_events(slot_id), *decision_partition_events ].each do |event|
      decision_projector.call(event)
    end
  end

  def project_decision_correction(decision_id)
    event = decision_events(decision_id).find { _1.type == "DecisionDefinitionCorrected" }
    assert_acceptance(event, "Decision #{decision_id} has no DecisionDefinitionCorrected fact")
    decision_projector.call(event)
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
    Coordinator::Container["projectors.agent_choices_v1"].call(event)
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
        repository_ids: [ "billing" ],
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
    process_manager = Coordinator::Container["process_managers.agent_choice_decision_impact"]
    process_manager.call(source)
    started = impact_scan_events(source).find { _1.type == "AgentChoiceImpactScanStarted" }
    assert_acceptance(started, "Decision change #{source.id} did not start an impact scan")
    process_manager.call(started)
    process_manager.call(source)
    process_manager.call(started)
    completed = impact_scan_events(source).find { _1.type == "AgentChoiceImpactScanCompleted" }
    assert_acceptance(completed, "Decision change #{source.id} did not complete its impact scan")
    { started:, completed: }
  end

  def impact_scan_events(source)
    scan_id = Coordinator::Write::AgentChoiceImpacts::ScanIdentityBuilder.new.start(
      source_event: impact_event_reference(source),
      policy_version: IMPACT_POLICY_VERSION
    )
    event_store.read_grouped(
      streams.agent_choice_impact_scan(scan_id),
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
    assessment_id = Coordinator::Write::AgentChoiceImpacts::AssessmentIdentityBuilder.new.call(
      accepted_choice: impact_event_reference(accepted),
      decision_change: impact_event_reference(source),
      policy_version: IMPACT_POLICY_VERSION
    )
    event_store.read(
      streams.agent_choice_impact(assessment_id),
      Coordinator::Write::EventQueries::AGENT_CHOICE_IMPACT_ASSESSMENT
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
    Coordinator::Container["projectors.agent_choice_impacts_v1"].call(event)
  end

  def project_choice_invalidation(choice_id)
    event = impact_choice_events(choice_id).find { _1.type == "AgentChoiceInvalidatedByDecision" }
    assert_acceptance(event, "AgentChoice #{choice_id} has no invalidation")
    Coordinator::Container["projectors.agent_choice_impacts_v1"].call(event)
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
      repository_ids: [ "billing" ],
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
        repository_ids: [ "billing" ],
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

  def lease_events(path)
    resource = Coordinator::Write::FileResourceNormalizer.new.call(
      repository_id: "billing",
      kind: "file",
      path:,
      base_blob_oid: nil
    ).value!
    event_store.read(
      streams.resource_lease(resource.resource_key_hash),
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
      repository_id: "billing",
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

  private

  def decision_projector
    Coordinator::Container["projectors.decision_governance_v1"]
  end

  def mcp_session
    @mcp_session ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host! "localhost"
    end
  end

  def next_request_id
    @request_id = @request_id.to_i + 1
  end

  def modern_params(params)
    extensions = tasks_capable? ? { TASKS_EXTENSION => {} } : {}
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion": PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities": { extensions: },
        "io.modelcontextprotocol/clientInfo": { name: "cucumber", version: "1.0" }
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
