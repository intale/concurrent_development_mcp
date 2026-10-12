# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::WorkIntentionSetRenewal, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:loader) { Coordinator::Write::WorkIntentionRenewals::Loader.new(event_store:) }
  let(:intention_loader) { Coordinator::Write::WorkIntentionLoader.new(event_store:) }
  subject(:handler) { described_class.new(event_store:) }

  it "keeps the Task working until independently committed member steps and the root outcome finish" do
    command, task_id, request = plan_renewal
    expect(Coordinator::Write::Tasks::Loader.new(event_store:).call(task_id).state.status).to eq("working")
    expect(intention_events(command.intentions.first.intention_id).map(&:type)).to eq([ "ResourceWorkIntentionDeclared" ])
    handler.call(request)
    snapshot = loader.call(command.command_id)
    expect(snapshot.state.terminal.class).to eq(Coordinator::Write::Events::OptimisticSagas::WorkIntentionSetRenewalCompletedV1)
    expect(snapshot.state.outcomes.length).to eq(2)
    expect(Coordinator::Write::Tasks::Loader.new(event_store:).call(task_id).state.status).to eq("completed")
    ids = snapshot.events.map(&:id)
    handler.call(request)
    expect(loader.call(command.command_id).events.map(&:id)).to eq(ids)
    snapshot.state.assignments.each do |assignment|
      renewal = intention_events(assignment.intention_id).last
      expect(renewal.metadata).to include("command_id" => assignment.renew_command_id, "renewal_id" => command.command_id)
      expect(renewal.correlation_id).to eq(request.correlation_id)
      expect(intention_events(assignment.intention_id).count { _1.type == "ResourceWorkIntentionRenewed" }).to eq(1)
    end
  end

  it "preserves a completed member when another is withdrawn, and records a terminal partial failure" do
    command, task_id, request = plan_renewal
    snapshot = loader.call(command.command_id)
    first, second = snapshot.state.assignments
    dispatch_member(command, first, snapshot:)
    withdraw(command)
    handler.call(request)
    state = loader.call(command.command_id).state
    expect(state.failed_member).to have_attributes(intention_id: second.intention_id, reason_code: "work_intention_set_inactive")
    expect(state).to be_effects_committed
    expect(state.outcome(first.intention_id).class).to eq(Coordinator::Write::Events::OptimisticSagas::WorkIntentionRenewalCompletedV1)
    expect(intention_loader.call(first.intention_id).state.expires_at).to eq(state.request.expires_at)
    expect(intention_events(second.intention_id).map(&:type)).not_to include("ResourceWorkIntentionRenewed")
    canonical = Coordinator::Write::CommandLifecycle::Loader.new(event_store:).call(command.command_id)
    expect(canonical.state).to be_failed
    expect(canonical.state.execution_failure).to have_attributes(effects_committed: true, retryable: false, attempts: 1)
    expect(Coordinator::Write::Tasks::Loader.new(event_store:).call(task_id).state.status).to eq("completed")
    before = loader.call(command.command_id).events.map(&:id)
    handler.call(request)
    expect(loader.call(command.command_id).events.map(&:id)).to eq(before)
  end

  it "recovers an unrecorded member effect even after withdrawal" do
    command, = plan_renewal
    snapshot = loader.call(command.command_id)
    assignment = snapshot.state.assignments.first
    physical = renew(command, assignment, snapshot:)
    withdraw(command)
    replay = renew(command, assignment, snapshot:)
    expect(replay.id).to eq(physical.id)
    expect(intention_events(assignment.intention_id).count { _1.type == "ResourceWorkIntentionRenewed" }).to eq(1)
  end

  it "finalizes a completed Saga after an interruption without extending members again" do
    command, task_id, request = plan_renewal
    snapshot = loader.call(command.command_id)
    snapshot.state.assignments.each { dispatch_member(command, _1, snapshot:) }
    expect(loader.call(command.command_id).state.terminal).not_to be_nil
    expect(Coordinator::Write::CommandLifecycle::Loader.new(event_store:).call(command.command_id).state.status).to eq("registered")
    handler.call(request)
    expect(Coordinator::Write::Tasks::Loader.new(event_store:).call(task_id).state.status).to eq("completed")
    snapshot.state.assignments.each do |assignment|
      expect(intention_events(assignment.intention_id).count { _1.type == "ResourceWorkIntentionRenewed" }).to eq(1)
    end
  end

  it "records exactly three real optimistic member races as a retryable Saga failure" do
    command, task_id, request = plan_renewal
    snapshot = loader.call(command.command_id)
    victim = snapshot.state.assignments.first
    racers = [ 400, 500, 600 ].map.with_index do |ttl_seconds, index|
      input = command.class.new(command.attributes.merge(command_id: "competing-renewal-#{index}", ttl_seconds:))
      task = Coordinator::Write::Operations::SubmitCoordinationTask.new(event_store:).call(input).value!
      source = event_store.read(streams.coordination_task(task.task_id), Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY).first
      Coordinator::Processes::ProcessManagers::CoordinationTaskExecutor.new(event_store:).call(source)
      race = loader.call(task.command_id)
      assignment = race.state.assignments.find { _1.intention_id == victim.intention_id }
      [ input.class.new(input.attributes.merge(command_id: task.command_id)), race, assignment ]
    end
    competitors = Coordinator::Write::EventStore.new(client: PgEventstore.client)
    conflicts = 0
    trace = TracePoint.new(:call) do |frame|
      next unless frame.self.equal?(event_store) && frame.defined_class == Coordinator::Write::EventStore && frame.method_id == :append
      events = frame.binding.local_variable_get(:events)
      next unless events.first.metadata["command_id"] == victim.renew_command_id && conflicts < 3
      other_command, race, assignment = racers.fetch(conflicts)
      conflicts += 1
      child = member_command(other_command, assignment, snapshot: race)
      source = race.events.find { _1.type == "WorkIntentionRenewalAssigned" && _1.data.fetch("intention_id") == assignment.intention_id }
      Coordinator::Write::Operations::ExecuteRenewWorkIntention.new(event_store: competitors).call_command(child, caused_by: source).value!
    end
    trace.enable { handler.call(request) }
    expect(conflicts).to eq(3)
    state = loader.call(command.command_id).state
    expect(state.failed_member).to have_attributes(reason_code: "concurrency_conflict", attempts: 3, retryable: true)
    expect(state).not_to be_effects_committed
    canonical = Coordinator::Write::CommandLifecycle::Loader.new(event_store:).call(command.command_id)
    expect(canonical.state.execution_failure).to have_attributes(attempts: 3, retryable: true, effects_committed: false)
    expect(Coordinator::Write::Tasks::Loader.new(event_store:).call(task_id).state.status).to eq("completed")
  ensure
    trace&.disable
  end

  def plan_renewal
    WorkIntentionOperationScenario.start_attempts(event_store:, attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = WorkIntentionOperationScenario.declare(event_store:, paths: [ "app/a.rb", "app/b.rb" ], ttl_seconds: 300)
    input = Coordinator::Write::Operations::PrepareRenewWorkIntentionSet.new.call(
      command_id: "renewal-saga-test", actor: { kind: "agent", id: "agent-a" }, change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A", attempt_id: "A-LSE-A", intention_set_id: reservation.receipt.intention_set_id,
      intentions: WorkIntentionOperationScenario.work_intention_inputs(reservation.receipt), ttl_seconds: 900).value!
    task = Coordinator::Write::Operations::SubmitCoordinationTask.new(event_store:).call(input).value!
    submission = event_store.read(streams.coordination_task(task.task_id), Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY).first
    Coordinator::Processes::ProcessManagers::CoordinationTaskExecutor.new(event_store:).call(submission)
    command = input.class.new(input.attributes.merge(command_id: task.command_id))
    [ command, task.task_id, loader.call(task.command_id).events.first ]
  end

  def renew(command, assignment, snapshot:)
    child = member_command(command, assignment, snapshot:)
    source = snapshot.events.find { _1.type == "WorkIntentionRenewalAssigned" && _1.data.fetch("intention_id") == assignment.intention_id }
    Coordinator::Write::Operations::ExecuteRenewWorkIntention.new(event_store:).call_command(child, caused_by: source).value!
  end

  def member_command(command, assignment, snapshot:)
    Coordinator::Write::Commands::RenewWorkIntention.new(command_id: assignment.renew_command_id, actor: command.actor,
      renewal_id: command.command_id, intention_set_id: command.intention_set_id, change_set_id: command.change_set_id,
      work_item_id: command.work_item_id, attempt_id: command.attempt_id, intention_id: assignment.intention_id,
      resource_id: assignment.resource_id, fencing_token: assignment.fencing_token, expires_at: snapshot.state.request.expires_at)
  end

  def dispatch_member(command, assignment, snapshot:)
    physical = renew(command, assignment, snapshot:)
    reference = Coordinator::Write::EventReference.new(event_id: physical.id, type: physical.type,
      stream_context: physical.stream.context, stream_name: physical.stream.stream_name,
      stream_id: physical.stream.stream_id, stream_revision: physical.stream_revision)
    outcome = Coordinator::Write::Commands::RecordWorkIntentionRenewalOutcome.new(command_id: assignment.outcome_command_id,
      actor: command.actor, renewal_id: command.command_id, intention_id: assignment.intention_id, renewal_event: reference, failure: nil)
    Coordinator::Write::Operations::ExecuteRecordWorkIntentionRenewalOutcome.new(event_store:).call_command(outcome, caused_by: physical).value!
  end

  def withdraw(command)
    Coordinator::Write::Operations::ExecuteWithdrawWorkIntentionSet.new(event_store:).call(
      command_id: "withdraw-between-renewal-steps", actor: command.actor.to_h, change_set_id: command.change_set_id,
      work_item_id: command.work_item_id, attempt_id: command.attempt_id, intention_set_id: command.intention_set_id,
      intentions: command.intentions.map(&:to_h)).value!
  end

  def intention_events(intention_id)
    event_store.read_grouped(streams.resource_work_intention(intention_id), Coordinator::Write::EventQueries::WORK_INTENTION_STATE).reverse
  end
end
