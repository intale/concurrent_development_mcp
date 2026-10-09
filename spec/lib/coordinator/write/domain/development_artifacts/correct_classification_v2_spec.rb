# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::DevelopmentArtifacts::CorrectClassificationV2 do
  let(:observation_id) { SecureRandom.uuid_v7 }
  let(:artifact_id) { SecureRandom.uuid_v7 }
  let(:state) do
    Coordinator::Write::Domain::DevelopmentArtifacts::ObservationState.reduce([
      Coordinator::Write::Events::DevelopmentArtifactObservationRecordedV1.new(observation_id:),
      Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1.new(
        observation_id:,
        artifact_id:,
        role: "created",
        observed_fact: Coordinator::Write::EventReference.new(
          event_id: SecureRandom.uuid_v7,
          type: "DevelopmentArtifactCreated",
          stream_context: "DevelopmentMemory",
          stream_name: "DevelopmentArtifact",
          stream_id: artifact_id,
          stream_revision: 0
        )
      )
    ])
  end
  let(:command) do
    Coordinator::Write::Commands::CorrectDevelopmentArtifactClassification.new(
      command_id: "cmd-classification",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-1"),
      observation_id:,
      expected_revision: 1,
      title: "Corrected",
      kind: "contract",
      labels: %w[docs reviewed],
      reason: "Improve imported classification"
    )
  end

  let(:artifact_state) do
    Coordinator::Write::Domain::DevelopmentArtifacts::State.reduce([
      Coordinator::Write::Events::DevelopmentArtifactCreatedV1.new(artifact_id: state.artifact_id),
      Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1.new(
        artifact_id: state.artifact_id, title: "Original"
      ),
      Coordinator::Write::Events::DevelopmentArtifactKindChangedV1.new(
        artifact_id: state.artifact_id, kind: "documentation"
      ),
      Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1.new(
        artifact_id: state.artifact_id, label: "docs"
      )
    ])
  end

  it "records correction intent without embedding a classification snapshot" do
    references = 3.times.map do |index|
      Coordinator::Write::EventReference.new(
        event_id: SecureRandom.uuid_v7,
        type: "DevelopmentArtifactFact#{index}",
        stream_context: "DevelopmentMemory",
        stream_name: "DevelopmentArtifact",
        stream_id: state.artifact_id,
        stream_revision: index + 1
      )
    end
    result = described_class.new.call(
      state:,
      command:,
      artifact_state:,
      fact_event_references: references
    ).value!
    events = result.event_plan.events

    expect(events.map(&:class)).to eq([
      Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactKindChangedV1,
      Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1,
      Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectionRecordedV1,
      Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1,
      Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1,
      Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1
    ])
    expect(events.map(&:to_h).join).not_to include("corrected_at")
    expect(events.find { _1.is_a?(Coordinator::Write::Events::DevelopmentArtifactClassificationCorrectionRecordedV1) }.to_h)
      .to include(artifact_id: state.artifact_id, observation_id:, classification_revision: 2)
    links = events.drop(4)
    expect(links.map { _1.observed_fact.event_id }).to eq(references.map(&:event_id))
    expect(links.map(&:role)).to eq(%w[title kind label])
  end

  it "returns an existing decision for an unchanged classification" do
    unchanged = Coordinator::Write::Commands::CorrectDevelopmentArtifactClassification.new(
      command.to_h.merge(
        expected_revision: 1,
        title: "Original",
        kind: "documentation",
        labels: [ "docs" ]
      )
    )

    result = described_class.new.call(
      state:,
      command: unchanged,
      artifact_state:,
      fact_event_references: []
    ).value!

    expect(result).to have_attributes(
      artifact_id: state.artifact_id,
      classification_revision: 1,
      outcome: "existing",
      event_plan: nil,
      fact_event_ids: []
    )
  end

  it "rejects a stale classification revision with typed details" do
    stale = Coordinator::Write::Commands::CorrectDevelopmentArtifactClassification.new(
      command.to_h.merge(expected_revision: 2)
    )

    result = described_class.new.call(
      state:,
      command: stale,
      artifact_state:,
      fact_event_references: []
    )

    expect(result).to be_failure
    expect(result.failure.details).to eq(
      observation_id:,
      expected_revision: 2,
      current_revision: 1
    )
    expect(
      Coordinator::Write::Tasks::DomainErrorV1::Type[
        code: result.failure.code.to_s,
        message: result.failure.message,
        details: result.failure.details
      ]
    ).to be_a(Coordinator::Write::Tasks::DomainErrorV1::DevelopmentArtifactClassificationRevisionConflictError)
  end
end
