# frozen_string_literal: true

RSpec.describe Coordinator::Read::CommandResults::Assembler, :event_store do
  subject(:assemble) do
    lambda do |terminal|
      source = Coordinator::Read::CommandResults::SourceLoader.new(event_store:).call(terminal)
      described_class.new(event_store:).call(source)
    end
  end

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:event_factory) { Coordinator::Write::EventFactory.new }
  let(:command_id) { SecureRandom.uuid_v7 }
  let(:task_id) { SecureRandom.uuid_v7 }
  let(:occurred_at) { "2026-09-03T12:00:00.000000Z" }
  let(:canonical_input_digest) { "sha256:#{'a' * 64}" }
  let(:command) do
    Coordinator::Write::Commands::CreateChangeSet.new(
      command_id:,
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "assembly-spec"),
      change_set_id: "CS-command-result",
      goal: "Assemble a semantic command result",
      acceptance_criteria: [ "No presentation document is persisted as an event" ]
    )
  end

  it "assembles success from authoritative command and domain facts" do
    register_command
    append_task_submission
    domain_events = append_change_set_facts
    terminal = append_terminal(Coordinator::Write::Events::CommandSucceededV1.new(command_id:))

    result = assemble.call(terminal)

    expect(result).to have_attributes(
      command_id: "assembly-spec-request",
      tool_name: "change_set_create",
      status: "ok",
      receipt: "assembly-spec-request",
      completed_at: terminal.created_at.utc.iso8601(6)
    )
    expect(result.data).to have_attributes(change_set_id: "CS-command-result")
    expect(result.emitted_events.map(&:event_id)).to eq(domain_events.map(&:id))
    expect(result.semantic_result).to be_a(Coordinator::Write::Tasks::SemanticResultV1::Success)
  end

  it "assembles a typed rejection without a receipt" do
    register_command
    append_task_submission
    rejection = Coordinator::Write::Tasks::DomainErrorV1::ChangeSetError.new(
      code: "change_set_already_exists",
      message: "ChangeSet already exists",
      details: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetDetails.new(
        change_set_id: "CS-command-result"
      )
    )
    terminal = append_terminal(
      Coordinator::Write::Events::CommandRejectedV2.new(
        command_id:,
        error: rejection,
        retryable: false
      )
    )

    result = assemble.call(terminal)

    expect(result).to have_attributes(
      command_id: "assembly-spec-request",
      status: "denied",
      receipt: nil,
      summary: "ChangeSet already exists",
      completed_at: terminal.created_at.utc.iso8601(6)
    )
    expect(result.data).to eq(rejection)
    expect(result.semantic_result).to be_a(
      Coordinator::Write::Tasks::SemanticResultV1::DomainRejection
    )
  end

  it "does not build a public receipt for an internal policy command" do
    append(
      streams.command(command_id),
      Coordinator::Write::Events::CommandRegisteredV1.new(
        command_id:, request_id: "policy-request", tool_name: "coordination-policy"
      ),
      metadata: canonical_metadata, markers: [ "command:#{command_id}" ]
    )
    terminal = append_terminal(Coordinator::Write::Events::CommandSucceededV1.new(command_id:))

    expect(Coordinator::Read::CommandResults::SourceLoader.new(event_store:).call(terminal)).to be_nil
  end

  it "rejects a public Command whose client instruction is missing" do
    register_command
    terminal = append_terminal(Coordinator::Write::Events::CommandSucceededV1.new(command_id:))

    expect { Coordinator::Read::CommandResults::SourceLoader.new(event_store:).call(terminal) }
      .to raise_error(Coordinator::Read::InvalidProjectionSource, "Command has no Task or Operation Batch instruction")
  end

  context "when another Repository command won the same natural key" do
    let(:canonical_repository_id) { SecureRandom.uuid_v7 }
    let(:command) do
      Coordinator::Write::Commands::RegisterRepository.new(
        command_id:,
        actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "assembly-spec"),
        repository_id: SecureRandom.uuid_v7,
        scope: "project:command-result",
        repository_key: "shared-repository",
        display_name: "Shared Repository",
        paths: [],
        remotes: []
      )
    end

    it "assembles the canonical existing registration without an emitted event" do
      append_canonical_repository
      register_command
      append_task_submission
      terminal = append_terminal(
        Coordinator::Write::Events::CommandSucceededV1.new(command_id:)
      )

      result = assemble.call(terminal)

      expect(result.data).to have_attributes(
        repository_id: canonical_repository_id,
        scope: command.scope
      )
      expect(result.summary).to eq("Canonical Repository registration already exists for the exact scope and key.")
      expect(result.emitted_events).to be_empty
    end
  end

  context "when another proposed Artifact UUID captured the canonical bytes" do
    let(:canonical_artifact_id) { SecureRandom.uuid_v7 }
    let(:proposed_artifact_id) { SecureRandom.uuid_v7 }
    let(:observation_id) { SecureRandom.uuid_v7 }
    let(:source) do
      Coordinator::Write::DevelopmentArtifacts::SourceV1.new(
        kind: "local_file",
        locator: "docs/canonical.md",
        revision: "abc123",
        observed_at: occurred_at,
        collector: "assembly-spec/v1"
      )
    end
    let(:content) do
      Coordinator::Write::DevelopmentArtifacts::ContentBuilder.new.call(
        encoding: "utf-8",
        media_type: "text/markdown",
        text: "canonical bytes\n"
      ).value!
    end
    let(:proposed_artifact) do
      Coordinator::Write::DevelopmentArtifacts::ArtifactV2.new(
        artifact_id: proposed_artifact_id,
        scope: "project:command-result",
        title: "Canonical bytes",
        kind: "documentation",
        labels: %w[canonical docs],
        content:,
        source:
      )
    end
    let(:proposed_observation) do
      Coordinator::Write::DevelopmentArtifacts::ArtifactObservationV1.new(
        observation_id:,
        artifact_id: proposed_artifact_id,
        scope: proposed_artifact.scope,
        title: proposed_artifact.title,
        kind: proposed_artifact.kind,
        labels: proposed_artifact.labels,
        source:
      )
    end
    let(:command) do
      Coordinator::Write::Commands::CaptureDevelopmentArtifact.new(
        command_id:,
        actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "assembly-spec"),
        artifact: proposed_artifact,
        observation: proposed_observation
      )
    end

    it "assembles the canonical Artifact from the new observation" do
      append_canonical_artifact
      register_command
      append_task_submission
      observation = append_canonical_artifact_observation
      terminal = append_terminal(Coordinator::Write::Events::CommandSucceededV1.new(command_id:))

      result = assemble.call(terminal)

      expect(canonical_artifact_id).not_to eq(proposed_artifact_id)
      expect(result.data).to have_attributes(
        artifact_id: canonical_artifact_id,
        observation_id:,
        outcome: "observed",
        content_sha256: content.content_sha256
      )
      expect(result.emitted_events.map(&:event_id)).to eq([ observation.id ])
    end
  end

  context "when another proposed Relation UUID declared the same natural relation" do
    let(:canonical_relation_id) { SecureRandom.uuid_v7 }
    let(:proposed_relation_id) { SecureRandom.uuid_v7 }
    let(:source_artifact_id) { SecureRandom.uuid_v7 }
    let(:target_artifact_id) { SecureRandom.uuid_v7 }
    let(:proposed_relation) do
      Coordinator::Write::DevelopmentArtifacts::RelationV1.new(
        relation_id: proposed_relation_id,
        source_artifact_id:,
        relation: "references",
        target: Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
          kind: "artifact",
          id: target_artifact_id
        ),
        attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(
          path: "child.md",
          normalized_locator: "docs/child.md"
        )
      )
    end
    let(:command) do
      Coordinator::Write::Commands::DeclareDevelopmentArtifactRelation.new(
        command_id:,
        actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "assembly-spec"),
        artifact_relation: proposed_relation
      )
    end

    it "assembles the canonical Relation selected by its natural-key marker" do
      append_canonical_artifact_relation
      register_command
      append_task_submission
      terminal = append_terminal(
        Coordinator::Write::Events::CommandSucceededV1.new(command_id:)
      )

      result = assemble.call(terminal)

      expect(canonical_relation_id).not_to eq(proposed_relation_id)
      expect(result.data).to have_attributes(
        relation_id: canonical_relation_id,
        source_artifact_id:,
        relation: "references",
        outcome: "existing"
      )
      expect(result.emitted_events).to be_empty
    end
  end

  context "when granular Artifact facts are emitted" do
    let(:artifact_id) { SecureRandom.uuid_v7 }
    let(:command) do
      Coordinator::Write::Commands::UpdateDevelopmentArtifact.new(
        command_id:,
        actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "assembly-spec"),
        artifact_id:,
        expected_revision: 4,
        changes: Coordinator::Write::DevelopmentArtifacts::UpdateChangesV1.new(title: "Updated")
      )
    end

    it "reconstructs changed properties and native event time" do
      register_command
      append_task_submission
      fact = append(
        streams.development_artifact(artifact_id),
        Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1.new(
          artifact_id:, title: "Updated"
        ),
        metadata: command_metadata(policy_version: "development-artifact-repository/v2"),
        markers: [ "development-artifact:#{artifact_id}", "command:#{command_id}" ]
      )
      terminal = append_terminal(Coordinator::Write::Events::CommandSucceededV1.new(command_id:))

      result = assemble.call(terminal)

      expect(result.data).to have_attributes(
        artifact_id:,
        resulting_stream_revision: fact.stream_revision,
        changed_properties: [ "title" ],
        outcome: "updated",
        updated_at: fact.created_at.utc.iso8601(6)
      )
    end
  end

  context "when a flat v2 Relation fact is emitted" do
    let(:source_artifact_id) { SecureRandom.uuid_v7 }
    let(:relation_id) { SecureRandom.uuid_v7 }
    let(:command) do
      Coordinator::Write::Commands::DeclareDevelopmentArtifactRelation.new(
        command_id:,
        actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "assembly-spec"),
        artifact_relation: Coordinator::Write::DevelopmentArtifacts::RelationV1.new(
          relation_id:,
          source_artifact_id:,
          relation: "references",
          target: Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
            kind: "external",
            id: "https://example.test/target"
          ),
          attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(
            path: nil,
            fragment: nil,
            normalized_locator: nil
          )
        )
      )
    end

    it "reconstructs the target status from the flat declaration" do
      register_command
      append_task_submission
      declaration = append(
        streams.development_artifact_relation(relation_id),
        Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV2.new(
          relation_id:,
          source_artifact_id:,
          relation: "references",
          target_kind: "external",
          target_id: "https://example.test/target",
          path: nil,
          fragment: nil,
          normalized_locator: nil
        ),
        metadata: command_metadata(policy_version: "development-artifact-repository/v2"),
        markers: [ "development-artifact-relation:#{relation_id}", "command:#{command_id}" ]
      )
      terminal = append_terminal(Coordinator::Write::Events::CommandSucceededV1.new(command_id:))

      result = assemble.call(terminal)

      expect(result.data.target).to have_attributes(
        kind: "external",
        id: "https://example.test/target",
        status: "unverified"
      )
      expect(result.data.declared_at).to eq(declaration.created_at.utc.iso8601(6))
    end
  end

  context "when a granular classification correction is recorded" do
    let(:artifact_id) { SecureRandom.uuid_v7 }
    let(:observation_id) { SecureRandom.uuid_v7 }
    let(:command) do
      Coordinator::Write::Commands::CorrectDevelopmentArtifactClassification.new(
        command_id:,
        actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "assembly-spec"),
        observation_id:,
        expected_revision: 1,
        title: "Corrected title",
        kind: "documentation",
        labels: [ "corrected" ],
        reason: "The initial classification was incomplete"
      )
    end

    it "uses correction-recorded revision, command values, and native event time" do
      register_command
      append_task_submission
      append(
        streams.development_artifact_observation(observation_id),
        Coordinator::Write::Events::DevelopmentArtifactObservationRecordedV1.new(
          observation_id:
        ),
        metadata: command_metadata(policy_version: "development-artifact-repository/v2"),
        markers: [ "development-artifact-observation:#{observation_id}" ]
      )
      correction = append(
        streams.development_artifact_observation(observation_id),
        Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectionRecordedV1.new(
          artifact_id:,
          observation_id:,
          classification_revision: 2,
          reason: command.reason
        ),
        metadata: command_metadata(policy_version: "development-artifact-repository/v2"),
        markers: [ "development-artifact:#{artifact_id}", "command:#{command_id}" ]
      )
      terminal = append_terminal(Coordinator::Write::Events::CommandSucceededV1.new(command_id:))

      result = assemble.call(terminal)

      expect(result.data).to have_attributes(
        artifact_id:,
        observation_id:,
        classification_revision: 2,
        title: "Corrected title",
        kind: "documentation",
        labels: [ "corrected" ],
        outcome: "corrected",
        corrected_at: correction.created_at.utc.iso8601(6)
      )
    end
  end

  context "when an Attempt is abandoned through granular lifecycle facts" do
    let(:intention_id) { SecureRandom.uuid_v7 }
    let(:resource_id) { SecureRandom.uuid_v7 }
    let(:set_id) { SecureRandom.uuid_v7 }
    let(:command) do
      Coordinator::Write::Commands::AbandonAttempt.new(
        command_id:,
        actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "assembly-spec"),
        change_set_id: "CS-command-result",
        work_item_id: "W-command-result",
        attempt_id: "A-command-result",
        reason: "Execution was interrupted after an intermediate checkpoint."
      )
    end

    it "reconstructs the receipt without an abandonment snapshot" do
      append_work_intention_set
      register_command
      append_task_submission
      append_abandonment_facts
      terminal = append_terminal(Coordinator::Write::Events::CommandSucceededV1.new(command_id:))

      result = assemble.call(terminal)

      expect(result).to have_attributes(
        status: "ok",
        summary: "Attempt abandoned; WorkItem requeued; 1 active work intention(s) withdrawn.",
        warnings: [ "Reacquire the WorkItem with a fresh Attempt ID and base snapshot before resuming." ]
      )
      expect(result.data).to have_attributes(
        change_set_id: command.change_set_id,
        work_item_id: command.work_item_id,
        attempt_id: command.attempt_id
      )
      expect(result.emitted_events.map(&:type)).to eq([
        "ResourceWorkIntentionWithdrawn",
        "AttemptAbandoned",
        "WorkItemRequeued"
      ])
    end

    def append_work_intention_set
      facts = [
        Coordinator::Write::Events::WorkIntentionSetCreatedV1.new(
          set_id:,
          attempt_id: command.attempt_id,
          work_item_id: command.work_item_id,
          change_set_id: command.change_set_id,
          repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID
        ),
        Coordinator::Write::Events::WorkIntentionAddedToSetV1.new(
          set_id:,
          intention_id:,
          resource_id:
        )
      ]
      facts.each do |fact|
        append(
          streams.work_intention_set(set_id),
          fact,
          metadata: command_metadata,
          markers: [ "attempt:#{command.attempt_id}", "work-intention-set:#{set_id}" ]
        )
      end
    end

    def append_abandonment_facts
      [
        [
          streams.resource_work_intention(intention_id),
          Coordinator::Write::Events::ResourceWorkIntentionWithdrawnV1.new(
            intention_id:,
            resource_id:,
            fencing_token: 1,
            reason: command.reason
          )
        ],
        [
          streams.attempt(command.attempt_id),
          Coordinator::Write::Events::AttemptAbandonedV3.new(
            attempt_id: command.attempt_id,
            reason: command.reason
          )
        ],
        [
          streams.work_item(command.work_item_id),
          Coordinator::Write::Events::WorkItemRequeuedV2.new(
            work_item_id: command.work_item_id,
            change_set_id: command.change_set_id,
            attempt_id: command.attempt_id,
            agent_id: command.actor.id,
            reason: command.reason
          )
        ]
      ].map do |stream, fact|
        append(
          stream,
          fact,
          metadata: command_metadata,
          markers: [ "command:#{command_id}", "attempt:#{command.attempt_id}" ]
        )
      end
    end
  end

  def register_command
    append(
      streams.command(command_id),
      Coordinator::Write::Events::CommandRegisteredV1.new(
        command_id:,
        request_id: "assembly-spec-request",
        tool_name:
      ),
      metadata: canonical_metadata,
      markers: [ "command:#{command_id}" ]
    )
  end

  def append_task_submission
    append(
      streams.coordination_task(task_id),
      Coordinator::Write::Events::CoordinationTaskSubmittedV3.new(
        task_id:,
        command_id:,
        tool_name:,
        command_input: Coordinator::Write::CommandInputDigest.new.document(command),
        poll_interval_ms: 500,
        ttl_ms: nil
      ),
      metadata: canonical_metadata,
      markers: [ "task:#{task_id}", "command:#{command_id}" ]
    )
  end

  def append_change_set_facts
    [
      Coordinator::Write::Events::ChangeSetCreatedV1.new(
        change_set_id: "CS-command-result",
        goal: command.goal,
        created_at: occurred_at
      ),
      Coordinator::Write::Events::ChangeSetAcceptanceCriteriaDefinedV1.new(
        change_set_id: "CS-command-result",
        acceptance_criteria: command.acceptance_criteria,
        defined_at: occurred_at
      )
    ].map do |payload|
      append(
        streams.change_set("CS-command-result"),
        payload,
        metadata: command_metadata,
        markers: [ "command:#{command_id}" ]
      )
    end
  end

  def append_canonical_repository
    marker = Coordinator::Write::Repositories::NaturalKeyMarker.new.call(
      scope: command.scope,
      repository_key: command.repository_key
    )
    append(
      streams.repository(canonical_repository_id),
      Coordinator::Write::Events::RepositoryRegisteredV1.new(
        repository_id: canonical_repository_id,
        scope: command.scope,
        repository_key: command.repository_key,
        display_name: command.display_name,
        paths: command.paths,
        remotes: command.remotes,
        registered_at: occurred_at
      ),
      metadata: command_metadata,
      markers: [ marker.marker ]
    )
  end

  def append_canonical_artifact
    source_command_id = SecureRandom.uuid_v7
    artifact = Coordinator::Write::DevelopmentArtifacts::ArtifactV2.new(
      proposed_artifact.to_h.merge(artifact_id: canonical_artifact_id)
    )
    payload = Coordinator::Write::Events::DevelopmentArtifactCapturedV2.new(
      artifact:,
      captured_at: occurred_at
    )
    append(
      streams.development_artifact(canonical_artifact_id),
      payload,
      metadata: command_metadata(
        command_id: source_command_id,
        policy_version: "development-artifact-repository/v1"
      ),
      markers: Coordinator::Write::DevelopmentArtifacts::MarkerBuilder.new.capture(
        event: payload,
        command_id: source_command_id
      )
    )
  end

  def append_canonical_artifact_observation
    observation = Coordinator::Write::DevelopmentArtifacts::ArtifactObservationV1.new(
      proposed_observation.to_h.merge(artifact_id: canonical_artifact_id)
    )
    payload = Coordinator::Write::Events::DevelopmentArtifactObservedV1.new(
      observation:,
      recorded_at: occurred_at
    )
    append(
      streams.development_artifact_observation(observation_id),
      payload,
      metadata: command_metadata(policy_version: "development-artifact-repository/v1"),
      markers: Coordinator::Write::DevelopmentArtifacts::MarkerBuilder.new.capture(
        event: payload,
        command_id:
      )
    )
  end

  def append_canonical_artifact_relation
    source_command_id = SecureRandom.uuid_v7
    relation = Coordinator::Write::DevelopmentArtifacts::RelationV1.new(
      proposed_relation.to_h.merge(relation_id: canonical_relation_id)
    )
    payload = Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV1.new(
      artifact_relation: relation,
      declared_at: occurred_at
    )
    append(
      streams.development_artifact(source_artifact_id),
      payload,
      metadata: command_metadata(
        command_id: source_command_id,
        policy_version: "development-artifact-repository/v1"
      ),
      markers: Coordinator::Write::DevelopmentArtifacts::MarkerBuilder.new.relation(
        artifact_relation: relation,
        command_id: source_command_id
      )
    )
  end

  def append_terminal(payload)
    append(
      streams.command(command_id),
      payload,
      metadata: Coordinator::Write::EventMetadata.new(
        command_id:,
        actor_kind: "agent",
        actor_id: "assembly-spec",
        recorded_by: "coordinator",
        policy_version: "command-lifecycle/v1"
      ),
      markers: [ "command:#{command_id}", "tool:#{tool_name}" ],
      expected_revision: 0
    )
  end

  def append(stream, payload, metadata:, markers:, expected_revision: nil)
    event = event_factory.build!(
      event: payload,
      event_id: SecureRandom.uuid_v7,
      metadata:,
      markers:
    )
    options = expected_revision.nil? ? {} : { expected_revision: }
    event_store.append(stream, [ event ], **options).sole
  end

  def canonical_metadata
    Coordinator::Write::Metadata::CanonicalCommandV1.new(
      command_id:,
      actor_kind: "agent",
      actor_id: "assembly-spec",
      recorded_by: "coordinator",
      policy_version: "coordination-task/v3",
      canonical_input_digest:
    )
  end

  def tool_name
    Coordinator::Write::Tasks::TargetContractRegistry.fetch_for(command).tool_name
  end

  def command_metadata(command_id: self.command_id, policy_version: "change-set/v1")
    Coordinator::Write::EventMetadata.new(
      command_id:,
      actor_kind: "agent",
      actor_id: "assembly-spec",
      recorded_by: "coordinator",
      policy_version:
    )
  end
end
