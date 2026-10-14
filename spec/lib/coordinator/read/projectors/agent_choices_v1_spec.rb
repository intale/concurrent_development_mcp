# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::AgentChoicesV1, :read_model do
  subject(:projector) { described_class.new }

  let(:choice_id) { "CHO-choice-project" }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000001" }
  let(:stream) { Coordinator::Write::StreamFactory.new.agent_choice(choice_id) }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "projects recorded and accepted evidence idempotently without withholding either stage" do
    recorded, accepted = choice_events

    projector.call([ recorded ])
    projector.call([ recorded ])

    available = repository.fetch(choice_id)
    expect(available).to have_attributes(
      choice_type: "testing.framework",
      observation_status: "recorded",
      selected: have_attributes(option_id: "rspec"),
      assessment: nil,
      accepted: nil
    )
    expect(available.recorded.to_h).to include(
      event: include(event_id: recorded.id, type: "AgentChoiceRecorded", stream_revision: 0),
      actor: include(kind: "agent", id: "agent-a", authenticated: false),
      markers: include("choice:#{choice_id}", "repository:#{repository_id}"),
      causation_id: recorded.causation_id,
      correlation_id: recorded.correlation_id
    )

    projector.call([ accepted ])
    projector.call([ accepted ])

    projected = repository.fetch(choice_id)
    expect(projected).to have_attributes(
      observation_status: "accepted",
      context_digest: decision_context.digest,
      assessment: have_attributes(basis: "no_policy", based_on_decisions: [], warnings: [])
    )
    expect(projected.accepted.to_h).to include(
      event: include(event_id: accepted.id, type: "AgentChoiceAccepted", stream_revision: 1),
      actor: include(kind: "agent", id: "agent-a", authenticated: false),
      markers: include("choice:#{choice_id}", "attempt:A-choice-project"),
      causation_id: accepted.causation_id,
      correlation_id: accepted.correlation_id
    )
    expect(Coordinator::Read::AgentChoice.count).to eq(1)
    expect(Coordinator::Read::ProcessedProjectionEvent.count).to eq(0)
  end

  it "patches acceptance without validating unrelated projected context" do
    row = create(:coordinator_read_agent_choice, choice_id:)
    original = row.attributes.slice("selected", "decision_context", "context_digest", "recorded_event")
    _, accepted = choice_events

    projector.call([ accepted ])

    expect(row.reload.observation_status).to eq("accepted")
    expect(row.attributes.slice(*original.keys)).to eq(original)
  end

  it "reconstructs projection-only context fields from narrow V2 evidence" do
    recorded, accepted = choice_events

    projector.call([ recorded, accepted ])

    projected = repository.fetch(choice_id)
    expect(projected).to have_attributes(
      observation_status: "accepted",
      context_digest: decision_context.digest,
      decision_context: have_attributes(
        document: decision_context.document,
        digest: decision_context.digest,
        resolved_at: recorded.created_at.utc.iso8601(6)
      )
    )
    expect(projected.accepted.metadata).to include("context_digest" => decision_context.digest)
  end

  it "preserves accepted-only columns when the registration portion is redelivered" do
    recorded, accepted = choice_events
    projector.call([ recorded, accepted ])
    row = Coordinator::Read::AgentChoice.find(choice_id)
    original = row.attributes.slice("observation_status", "assessment", "accepted_event", "accepted_metadata")

    projector.call([ recorded ])

    expect(row.reload.attributes.slice(*original.keys)).to eq(original)
  end

  it "updates a thousand independent accepted Choices through bounded compatible SQL statements" do
    rows = Array.new(1000) { attributes_for(:coordinator_read_agent_choice) }
    Coordinator::Read::AgentChoice.insert_all!(rows)
    _, prototype = choice_events
    events = rows.map.with_index do |attributes, index|
      event = prototype.dup
      event.id = SecureRandom.uuid_v7
      event.data = prototype.data.merge("choice_id" => attributes.fetch(:choice_id))
      event.stream = Coordinator::Write::PgStreamFactory.new.call(
        Coordinator::Write::StreamFactory.new.agent_choice(attributes.fetch(:choice_id))
      )
      event.global_position = prototype.global_position + index
      event
    end
    statements = []
    ActiveSupport::Notifications.subscribed(->(*args) { statements << args.last.fetch(:sql) }, "sql.active_record") do
      projector.call(events)
    end

    expect(statements.count { _1.start_with?("UPDATE") }).to be_between(1, 2)
    expect(Coordinator::Read::AgentChoice.where(observation_status: "accepted").count).to eq(1000)
  end

  def choice_events
    recorded = ProjectionEventFactory.build(
      payload: Coordinator::Write::Events::AgentChoiceRecordedV2.new(
        choice_id:,
        choice_type: "testing.framework",
        selected: { option_id: "rspec", summary: "Use RSpec" },
        alternatives: [],
        reason_summary: "RSpec is already established in the project.",
        context: query_context,
        decision_context: Coordinator::Write::DecisionContexts::EvidenceV2.new(
          document: decision_context.document
        )
      ),
      stream:,
      stream_revision: 0,
      global_position: 100,
      command_id: "cmd-choice-project-choice",
      actor_id: "agent-a",
      policy_version: "testing-framework-resolution/v1",
      correlation_id:,
      markers: [ "choice:#{choice_id}", "repository:#{repository_id}" ]
    )
    accepted = ProjectionEventFactory.build(
      payload: Coordinator::Write::Events::AgentChoiceAcceptedV2.new(
        choice_id:,
        assessment: { basis: "no_policy", based_on_decisions: [], warnings: [] }
      ),
      stream:,
      stream_revision: 1,
      global_position: 200,
      policy_version: "testing-framework-resolution/v1",
      correlation_id:,
      causation_id: recorded.id,
      markers: [ "choice:#{choice_id}", "attempt:A-choice-project" ],
      metadata: Coordinator::Write::Metadata::AgentChoiceAcceptanceV2.new(
        command_id: "cmd-choice-project-choice",
        actor_kind: "agent",
        actor_id: "agent-a",
        recorded_by: "coordinator",
        policy_version: "testing-framework-resolution/v1",
        context_digest: decision_context.digest
      )
    )
    [ recorded, accepted ]
  end

  def query_context
    @query_context ||= Coordinator::Write::DecisionContexts::QueryContextV1.new(
      workspace_id: nil,
      repository_id:,
      change_set_id: "CS-choice-project",
      work_item_id: "W-choice-project",
      attempt_id: "A-choice-project",
      phase: "implementation",
      language: "ruby",
      paths: [ "spec/models/example_spec.rb" ],
      environment: "test",
      agent_role: "developer"
    )
  end

  def decision_context
    @decision_context ||= begin
      observations = Coordinator::Write::DecisionContexts::PartitionSelector.new.call(query_context).map do |partition|
        Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
          partition:,
          partition_revision: nil,
          event: nil,
          active_decisions: []
        )
      end
      resolution = Coordinator::Write::DecisionContexts::ResultV1.new(
        effective_decision: nil,
        shadowed_decisions: [],
        conflict: nil,
        unsupported_dimensions: [],
        unsupported_decisions: [],
        unresolved_decisions: []
      )
      Coordinator::Write::DecisionContexts::Builder.new.call(
        context: query_context,
        observations:,
        resolution:,
        resolved_at: "2026-08-30T12:00:00.000000Z"
      )
    end
  end

  def event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def repository
    @repository ||= Coordinator::Read::Repositories::AgentChoices.new
  end
end
