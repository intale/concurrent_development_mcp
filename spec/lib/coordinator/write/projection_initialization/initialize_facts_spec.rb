# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteInitializeProjectionFacts, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:operation) { described_class.new(event_store:) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:id) { SecureRandom.uuid_v7 }
  let(:actor) { Coordinator::Write::Commands::Actor.new(kind: "system", id: "initialization-spec") }
  let(:correlation) { SecureRandom.uuid_v7 }

  def fact(stream, type, data, metadata: {})
    event_store.append(stream, [ PgEventstore::Event.new(type:, data:, metadata: { "schema_version" => 1 }.merge(metadata),
      correlation_id: correlation) ]).sole
  end

  def command(source)
    reference = Coordinator::Write::EventReference.new(event_id: source.id, type: source.type,
      stream_context: source.stream.context, stream_name: source.stream.stream_name,
      stream_id: source.stream.stream_id, stream_revision: source.stream_revision)
    Coordinator::Write::Commands::InitializeProjectionFacts.new(command_id: SecureRandom.uuid_v7, actor:, source_event: reference)
  end

  def initialize_source(source)
    operation.call_command(command(source)).value!
  end

  def skill_source
    fact(streams.skill_revision(id), "SkillRevisionCreated", { "skill_revision_id" => id, "skill_id" => SecureRandom.uuid_v7, "revision" => 1 })
  end

  def add_asset
    fact(streams.skill_revision(id), "SkillAssetAddedToRevision", { "skill_revision_id" => id, "asset_id" => SecureRandom.uuid_v7 })
  end

  it "initializes immutable Skill representation once without publishing a new logical revision" do
    source = skill_source
    2.times { add_asset }
    created = initialize_source(source).sole
    expect(created.type).to eq("SkillRevisionRepresentationRecorded")
    expect(created.data).to eq("skill_revision_id" => id)
    expect(created.metadata.fetch("asset_count")).to eq(2)
    expect(created.causation_id).to eq(source.id)
    expect(created.correlation_id).to eq(source.correlation_id)
    expect(created.created_at).to be >= source.created_at
    expect(created.metadata).not_to have_key("correlation_id")
    expect(initialize_source(source)).to be_empty
    expect(event_store.stream_head(streams.skill_revision(id)).stream_revision).to eq(3)
  end

  it "initializes Batch representation and absolute outcomes from authoritative item facts" do
    stream = streams.operation_batch(id)
    source = fact(stream, "OperationBatchCreated", { "batch_id" => id })
    3.times do |index|
      fact(stream, "OperationBatchItemEnqueued", { "batch_id" => id, "index" => index, "input" => { "name" => "item-#{index}" } },
        metadata: { "encoded_byte_size" => 20 })
    end
    fact(stream, "OperationBatchItemSucceeded", { "batch_id" => id, "index" => 0 })
    fact(stream, "OperationBatchItemRegistrationRejected", { "batch_id" => id, "index" => 1 })
    fact(stream, "OperationBatchItemFailed", { "batch_id" => id, "index" => 2 })
    fact(stream, "OperationBatchCompleted", { "batch_id" => id })

    facts = initialize_source(source)
    expect(facts.map(&:type)).to eq(%w[OperationBatchManifestAccepted OperationBatchSucceededItemsNumberChanged OperationBatchUnsuccessfulItemsNumberChanged OperationBatchOutcomeRecorded])
    expect(facts.first.metadata).to include("item_count" => 3, "encoded_byte_size" => 60)
    expect(facts[1].data).to eq("batch_id" => id, "items_number" => 1)
    expect(facts[2].data).to eq("batch_id" => id, "items_number" => 2)
    expect(facts.last.data).to eq("batch_id" => id, "outcome" => "completed_with_errors")
    expect(initialize_source(source)).to be_empty
  end

  it "adds only absent facts and preserves an already-modeled Batch count" do
    stream = streams.operation_batch(id)
    source = fact(stream, "OperationBatchCreated", { "batch_id" => id })
    fact(stream, "OperationBatchItemEnqueued", { "batch_id" => id, "index" => 0, "input" => { "name" => "item" } })
    fact(stream, "OperationBatchSucceededItemsNumberChanged", { "batch_id" => id, "items_number" => 7 })
    facts = initialize_source(source)
    expect(facts.map(&:type)).to eq(%w[OperationBatchManifestAccepted OperationBatchUnsuccessfulItemsNumberChanged])
    expect(initialize_source(source)).to be_empty
  end

  it "initializes required evidence coverage without consulting Candidate or Read state" do
    obligation_id = "obligation-readable-identity"
    stream = streams.verification_obligation(obligation_id)
    kinds = Coordinator::Write::Types::CANDIDATE_IMPACT_REQUIRED_EVIDENCE_KINDS.first(2)
    source = fact(stream, "VerificationObligationCreated", { "obligation_id" => obligation_id, "required_evidence" => kinds })
    fact(stream, "VerificationEvidenceSubmitted", { "obligation_id" => obligation_id, "evidence_id" => SecureRandom.uuid_v7,
      "evidence_kind" => kinds.first, "assessment" => { "conclusion" => "passed" } })
    fact(stream, "VerificationEvidenceSubmitted", { "obligation_id" => obligation_id, "evidence_id" => SecureRandom.uuid_v7,
      "evidence_kind" => kinds.last, "assessment" => { "conclusion" => "failed" } })
    facts = initialize_source(source)
    expect(facts.map { _1.data.fetch("obligation_id") }).to eq([ obligation_id, obligation_id ])
    expect(facts.first.data.fetch("evidence_number")).to eq(2)
    expect(facts.last.data).to include("passed_evidence_kinds" => [ kinds.first ], "missing_evidence_kinds" => [ kinds.last ])
    expect(initialize_source(source)).to be_empty
  end

  it "counts long Decision correction history through bounded type-filtered pages" do
    stream = streams.decision(id)
    source = fact(stream, "DecisionActivated", { "decision_id" => id })
    corrections = Array.new(1001) { PgEventstore::Event.new(type: "DecisionDefinitionCorrected", data: { "decision_id" => id }) }
    event_store.append(stream, corrections)
    observed = []
    trace = TracePoint.new(:call) do |point|
      observed << point.binding.local_variable_get(:criteria) if point.self.equal?(event_store) && point.method_id == :read_stream_history_page
    end
    created = trace.enable { initialize_source(source) }.sole
    expect(created.data.fetch("corrections_number")).to eq(1001)
    expect(observed.map(&:page_size)).to eq([ 1000, 1000, 1000 ])
    expect(observed.map(&:from_revision)).to eq([ 0, 1001, 1002 ])
    expect(observed.map(&:event_types)).to all(eq([ "DecisionDefinitionCorrected" ]))
  ensure
    trace&.disable
  end

  it "does not regress a terminal ReleaseSet to verification during initialization" do
    stream = streams.release_set(id)
    source = fact(stream, "ReleaseSetPrepared", { "release_set_id" => id })
    repository_id = SecureRandom.uuid_v7
    fact(stream, "ReleaseSetMemberAdded", { "release_set_id" => id, "repository_id" => repository_id })
    fact(stream, "RepositoryIntegrationRecorded", { "release_set_id" => id, "repository_id" => repository_id, "outcome" => "integrated" })
    fact(stream, "RepositoryIntegrationMergeLinked", { "release_set_id" => id, "repository_id" => repository_id })
    fact(stream, "ReleaseSetCompleted", { "release_set_id" => id })
    expect(initialize_source(source)).to be_empty
  end

  it "records a missing ReleaseSet verification transition only after every member is integrated and linked" do
    stream = streams.release_set(id)
    source = fact(stream, "ReleaseSetPrepared", { "release_set_id" => id })
    repository_id = SecureRandom.uuid_v7
    fact(stream, "ReleaseSetMemberAdded", { "release_set_id" => id, "repository_id" => repository_id })
    fact(stream, "RepositoryIntegrationRecorded", { "release_set_id" => id, "repository_id" => repository_id, "outcome" => "integrated" })
    expect(initialize_source(source)).to be_empty
    fact(stream, "RepositoryIntegrationMergeLinked", { "release_set_id" => id, "repository_id" => repository_id })
    expect(initialize_source(source).map(&:type)).to eq([ "ReleaseSetVerificationRequested" ])
    expect(initialize_source(source)).to be_empty
  end

  it "denies a source whose event ID is not the persisted owner fact" do
    source = skill_source
    valid = command(source)
    invalid = Coordinator::Write::Commands::InitializeProjectionFacts.new(command_id: valid.command_id, actor:,
      source_event: valid.source_event.new(event_id: SecureRandom.uuid_v7))
    result = operation.call_command(invalid)
    expect(result.failure.code).to eq(:projection_initialization_source_invalid)
    expect(event_store.stream_head(streams.skill_revision(id)).id).to eq(source.id)
  end

  it "rereads after a real concurrent append and initializes the resulting current count" do
    source = skill_source
    loader = Coordinator::Write::ProjectionInitialization::SourceLoader.new(event_store:)
    competing = false
    trace = TracePoint.new(:return) do |point|
      next unless point.self.equal?(loader) && point.method_id == :call && !competing

      competing = true
      add_asset
    end
    execute = described_class.new(event_store:, loader:)
    result = trace.enable { execute.call_command(command(source)) }
    expect(result.value!.sole.metadata.fetch("asset_count")).to eq(1)
    expect(initialize_source(source)).to be_empty
  ensure
    trace&.disable
  end

  it "exhausts three real revision races without partially appending representation facts" do
    source = skill_source
    loader = Coordinator::Write::ProjectionInitialization::SourceLoader.new(event_store:)
    races = 0
    trace = TracePoint.new(:return) do |point|
      next unless point.self.equal?(loader) && point.method_id == :call

      races += 1
      add_asset
    end
    execute = described_class.new(event_store:, loader:)
    result = trace.enable { execute.call_command(command(source)) }
    expect(result.failure.code).to eq(:projection_initialization_concurrency_conflict)
    expect(result.failure.details).to include(attempts: 3, retryable: true)
    expect(races).to eq(3)
    expect(initialize_source(source).sole.metadata.fetch("asset_count")).to eq(3)
  ensure
    trace&.disable
  end
end
