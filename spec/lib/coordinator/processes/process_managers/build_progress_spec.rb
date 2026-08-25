# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::BuildProgress, :event_store do
  subject(:process_manager) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "satisfies an exact output edge, unlocks the final consumer, and replays idempotently" do
    scenario = DependencyProgressScenario.prepare(
      prefix: "artifact-success",
      dependency_kind: "requires_artifact",
      required_output: { kind: "artifact", key: "billing-gem" }
    )
    completed = DependencyProgressScenario.complete(
      scenario,
      produced_outputs: [ { kind: "artifact", key: "billing-gem" } ]
    )
    source = DependencyProgressScenario.work_item_event(completed, "WorkItemCompleted")

    expect(process_manager.call(source)).to be_nil
    expect(process_manager.call(source)).to be_nil

    satisfaction = DependencyProgressScenario.dependency_events(completed).sole
    readiness = DependencyProgressScenario.readiness_events(completed).sole
    expect(satisfaction.data).to include(
      "dependency_kind" => "requires_artifact",
      "required_output" => { "kind" => "artifact", "key" => "billing-gem" }
    )
    expect(readiness.data).to include("reason" => "dependencies_satisfied")
    expect([ satisfaction.causation_id, readiness.causation_id ]).to eq([ source.id, source.id ])
    expect([ satisfaction, readiness ].map(&:correlation_id).uniq).to eq([ source.correlation_id ])
    expect(satisfaction.metadata).not_to have_key("correlation_id")

    command_id = satisfaction.metadata.fetch("command_id")
    command_completion = event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    ).sole
    expect(command_completion.causation_id).to eq(source.id)
    expect(command_completion.correlation_id).to eq(source.correlation_id)
  end

  it "treats a nonmatching output as an expected zero-event decision" do
    scenario = DependencyProgressScenario.prepare(
      prefix: "artifact-mismatch",
      dependency_kind: "requires_artifact",
      required_output: { kind: "artifact", key: "expected" }
    )
    completed = DependencyProgressScenario.complete(
      scenario,
      produced_outputs: [ { kind: "artifact", key: "other" } ]
    )
    source = DependencyProgressScenario.work_item_event(completed, "WorkItemCompleted")

    expect(process_manager.call(source)).to be_nil
    expect(DependencyProgressScenario.dependency_events(completed)).to be_empty
    expect(DependencyProgressScenario.readiness_events(completed)).to be_empty
  end

  it "converges concurrent delivery of one exact source to one satisfaction and one readiness fact" do
    scenario = DependencyProgressScenario.prepare(
      prefix: "candidate-race",
      dependency_kind: "requires_candidate"
    )
    completed = DependencyProgressScenario.complete(scenario)
    source = DependencyProgressScenario.work_item_event(completed, "WorkItemCandidateSelected")

    results = 2.times.map do
      Thread.new { described_class.new(event_store:).call(source) }
    end.map(&:value)

    expect(results).to eq([ nil, nil ])
    expect(DependencyProgressScenario.dependency_events(completed).length).to eq(1)
    expect(DependencyProgressScenario.readiness_events(completed).length).to eq(1)
  end

  it "processes terminal WorkItem facts through the real shared subscription set" do
    scenario = DependencyProgressScenario.prepare(
      prefix: "live-subscription",
      dependency_kind: "requires_completion"
    )
    registration = Coordinator::Processes::Subscriptions::BuildProgress.new(
      handler: process_manager,
      pull_interval: 0.2
    )
    manager = PgEventstore.subscriptions_manager(
      subscription_set: Coordinator::Processes::Subscriptions::ProcessManagerSet::SET_NAME
    )
    subscription_set = Coordinator::Processes::Subscriptions::ProcessManagerSet.new(
      manager:,
      registrations: [ registration ]
    )

    begin
      subscription_set.start
      completed = DependencyProgressScenario.complete(scenario)
      wait_for_satisfaction(completed)

      expect(DependencyProgressScenario.dependency_events(completed).length).to eq(1)
      expect(DependencyProgressScenario.readiness_events(completed).length).to eq(1)
    ensure
      subscription_set.stop
    end
  end

  it "loads exact ReleaseSet integration, verification, and activated-completion sources" do
    integration = ReleaseSetScenario.prepare(
      prefix: "dependency-integration",
      dependency: { kind: "must_integrate_after" }
    )
    observation = ReleaseSetScenario.observe_member(integration, index: 0, prefix: "dependency-integration")
    integrated = ReleaseSetScenario.record_integration(
      integration,
      index: 0,
      prefix: "dependency-integration",
      observation:
    )
    expect(process_manager.call(integrated.fetch(:event))).to be_nil
    expect(release_dependency_events(integration).length).to eq(1)

    verification = ReleaseSetScenario.prepare(
      prefix: "dependency-verification",
      dependency: {
        kind: "requires_composite_verification",
        required_output: { kind: "verification_run", key: "release-verification-dependency-verification" }
      }
    )
    integrations = ReleaseSetScenario.integrate_all(verification, prefix: "dependency-verification")
    verified = ReleaseSetScenario.record_verification(
      verification,
      integrations:,
      prefix: "dependency-verification"
    )
    expect(process_manager.call(verified.fetch(:event))).to be_nil
    expect(release_dependency_events(verification).length).to eq(1)

    deployment = ReleaseSetScenario.prepare(
      prefix: "dependency-deployment",
      dependency: { kind: "must_deploy_after" }
    )
    integrations = ReleaseSetScenario.integrate_all(deployment, prefix: "dependency-deployment")
    verification = ReleaseSetScenario.record_verification(
      deployment,
      integrations:,
      prefix: "dependency-deployment"
    )
    activation = ReleaseSetScenario.record_activation(
      deployment,
      verification:,
      prefix: "dependency-deployment"
    )
    Coordinator::Processes::ProcessManagers::ReleaseSetLifecycle.new(event_store:).call(activation.fetch(:event))
    completion = ReleaseSetScenario.release_lifecycle_events(
      deployment.dig(:input, :release_set_id)
    ).find { _1.type == "ReleaseSetCompleted" }
    expect(process_manager.call(completion)).to be_nil
    expect(release_dependency_events(deployment).length).to eq(1)
  end

  it "completes a single-repository ChangeSet from exact WorkItem evidence once" do
    candidate = CandidateScenario.submit(prefix: "change-set-single")
    completed = CandidateScenario.complete(candidate)
    source = event_store.read(
      streams.work_item(completed.dig(:input, :work_item_id)),
      Coordinator::Write::EventQueries::WORK_ITEM_FOR_CHANGE_SET_COMPLETION
    ).find { _1.type == "WorkItemCompleted" }

    expect(process_manager.call(source)).to be_nil
    expect(process_manager.call(source)).to be_nil

    completion = change_set_completion(completed.dig(:input, :change_set_id))
    payload = ReleaseSetScenario.load(completion)
    expect(payload.work_item_completions.map(&:work_item_id)).to eq([
      completed.dig(:input, :work_item_id)
    ])
    expect(payload.release_set_completion_event).to be_nil
    expect(completion.causation_id).to eq(source.id)
    expect(completion.correlation_id).to eq(source.correlation_id)
  end

  it "waits for an exact activated ReleaseSet before completing a multi-repository ChangeSet" do
    prepared = ReleaseSetScenario.prepare(prefix: "change-set-multi")
    work_item_sources(prepared).each { process_manager.call(_1) }
    expect(change_set_completions(prepared.fetch(:payload).change_set_id)).to be_empty

    integrations = ReleaseSetScenario.integrate_all(prepared, prefix: "change-set-multi")
    verification = ReleaseSetScenario.record_verification(
      prepared,
      integrations:,
      prefix: "change-set-multi"
    )
    activation = ReleaseSetScenario.record_activation(
      prepared,
      verification:,
      prefix: "change-set-multi"
    )
    Coordinator::Processes::ProcessManagers::ReleaseSetLifecycle.new(event_store:).call(
      activation.fetch(:event)
    )
    release_completion = ReleaseSetScenario.release_lifecycle_events(
      prepared.dig(:input, :release_set_id)
    ).find { _1.type == "ReleaseSetCompleted" }

    expect(process_manager.call(release_completion)).to be_nil

    completion = change_set_completion(prepared.fetch(:payload).change_set_id)
    payload = ReleaseSetScenario.load(completion)
    expect(payload.work_item_completions.map(&:candidate_id).sort).to eq(
      prepared.fetch(:payload).ordered_members.flat_map do |member|
        member.ordered_candidates.map(&:candidate_id)
      end.sort
    )
    expect(payload.release_set_completion_event).to eq(
      ReleaseSetScenario.reference(release_completion)
    )
  end

  it "does not complete from a compensated ReleaseSet" do
    prepared = ReleaseSetScenario.prepare(prefix: "change-set-compensated")
    observation = ReleaseSetScenario.observe_member(
      prepared,
      index: 0,
      prefix: "change-set-compensated"
    )
    ReleaseSetScenario.record_integration(
      prepared,
      index: 0,
      prefix: "change-set-compensated",
      observation:
    )
    failure = ReleaseSetScenario.record_integration(
      prepared,
      index: 1,
      prefix: "change-set-compensated",
      failure: release_failure("change-set-compensated")
    )
    lifecycle = Coordinator::Processes::ProcessManagers::ReleaseSetLifecycle.new(event_store:)
    lifecycle.call(failure.fetch(:event))
    request = ReleaseSetScenario.release_lifecycle_events(
      prepared.dig(:input, :release_set_id)
    ).find { _1.type == "ReleaseSetCompensationRequested" }
    completion = ReleaseSetScenario.complete_compensation(
      prepared,
      request: { event: request, payload: ReleaseSetScenario.load(request) },
      prefix: "change-set-compensated"
    )

    expect(process_manager.call(completion.fetch(:event))).to be_nil
    expect(change_set_completions(prepared.fetch(:payload).change_set_id)).to be_empty
  end

  it "does not complete when an activated ReleaseSet omits a completed WorkItem result" do
    prepared = ReleaseSetScenario.prepare(
      prefix: "change-set-coverage",
      omit_completed_member: true
    )
    integrations = ReleaseSetScenario.integrate_all(prepared, prefix: "change-set-coverage")
    verification = ReleaseSetScenario.record_verification(
      prepared,
      integrations:,
      prefix: "change-set-coverage"
    )
    activation = ReleaseSetScenario.record_activation(
      prepared,
      verification:,
      prefix: "change-set-coverage"
    )
    Coordinator::Processes::ProcessManagers::ReleaseSetLifecycle.new(event_store:).call(
      activation.fetch(:event)
    )
    completion = ReleaseSetScenario.release_lifecycle_events(
      prepared.dig(:input, :release_set_id)
    ).find { _1.type == "ReleaseSetCompleted" }

    expect(process_manager.call(completion)).to be_nil
    expect(change_set_completions(prepared.fetch(:payload).change_set_id)).to be_empty
  end

  it "publishes one unique multi-stream subscription definition" do
    definition = Coordinator::Processes::Subscriptions::BuildProgress::DEFINITION

    expect(definition.set_name).to eq("coordinator-process-managers-v1")
    expect(definition.subscription_name).to eq("build-progress-v1")
    expect(definition.event_types).to eq(%w[
      WorkItemCandidateSelected
      WorkItemCompleted
      RepositoryIntegrationRecorded
      ReleaseSetVerificationRecorded
      ReleaseSetCompleted
    ])
    expect(definition.streams.map(&:to_h)).to eq([
      { context: "DevelopmentExecution", stream_name: "WorkItem" },
      { context: "DevelopmentIntegration", stream_name: "ReleaseSet" }
    ])
  end

  def wait_for_satisfaction(scenario)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until DependencyProgressScenario.dependency_events(scenario).any?
      raise "build-progress subscription did not converge within 10 seconds" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  end

  def release_dependency_events(prepared)
    event_store.read(
      streams.change_set(prepared.fetch(:payload).change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_DEPENDENCY_SATISFACTION
    ).select { _1.type == "WorkItemDependencySatisfied" }
  end

  def work_item_sources(prepared)
    prepared.fetch(:payload).ordered_members.flat_map(&:ordered_candidates).map do |candidate|
      event_store.read(
        streams.work_item(candidate.work_item_id),
        Coordinator::Write::EventQueries::WORK_ITEM_FOR_CHANGE_SET_COMPLETION
      ).find { _1.type == "WorkItemCompleted" }
    end
  end

  def change_set_completion(change_set_id)
    change_set_completions(change_set_id).sole
  end

  def change_set_completions(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_COMPLETION
    ).select { _1.type == "ChangeSetCompleted" }
  end

  def release_failure(prefix)
    {
      code: "deployment-failed",
      summary: "Repository integration failed",
      producer: { name: "release-adapter", version: "1.0.0" },
      run_id: "release-failure-#{prefix}",
      result_digest: "sha256:#{'d' * 64}",
      occurred_at: "2026-08-25T08:30:00.000000Z"
    }
  end
end
