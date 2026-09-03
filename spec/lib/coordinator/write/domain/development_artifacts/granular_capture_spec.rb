# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::DevelopmentArtifacts::GranularCapture do
  let(:content) do
    Coordinator::Write::DevelopmentArtifacts::ContentBuilder.new.call(
      encoding: "utf-8",
      media_type: "text/markdown",
      text: "# Hello\n"
    ).value!
  end
  let(:source) do
    Coordinator::Write::DevelopmentArtifacts::SourceV1.new(
      kind: "local_file",
      locator: "docs/hello.md",
      revision: "abc123",
      observed_at: "2026-09-03T12:00:00.000000Z",
      collector: "spec"
    )
  end
  let(:artifact) do
    Coordinator::Write::DevelopmentArtifacts::ArtifactBuilder.new.call(
      scope: "project:example",
      title: "Hello",
      kind: "documentation",
      labels: %w[docs welcome],
      content:,
      source:
    )
  end
  let(:observation) do
    Coordinator::Write::DevelopmentArtifacts::ObservationBuilder.new.call(artifact:)
  end

  it "emits property facts and links the observation without snapshot or occurrence fields" do
    references = 8.times.map do |index|
      Coordinator::Write::EventReference.new(
        event_id: SecureRandom.uuid_v7,
        type: "DevelopmentArtifactFact#{index}",
        stream_context: "DevelopmentMemory",
        stream_name: "DevelopmentArtifact",
        stream_id: artifact.artifact_id,
        stream_revision: index
      )
    end
    decision = described_class.new.call(
      artifact:,
      observation:,
      fact_event_references: references
    ).value!
    events = decision.event_plan.events

    expect(events.map(&:class)).to eq(
      [
        Coordinator::Write::Events::DevelopmentArtifactCreatedV1,
        Coordinator::Write::Events::DevelopmentArtifactScopeChangedV1,
        Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1,
        Coordinator::Write::Events::DevelopmentArtifactKindChangedV1,
        Coordinator::Write::Events::DevelopmentArtifactSourceChangedV1,
        Coordinator::Write::Events::DevelopmentArtifactContentChangedV1,
        Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1,
        Coordinator::Write::Events::DevelopmentArtifactLabelAddedV1,
        Coordinator::Write::Events::DevelopmentArtifactObservationRecordedV1,
        Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1,
        Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1,
        Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1,
        Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1,
        Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1,
        Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1,
        Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1,
        Coordinator::Write::Events::DevelopmentArtifactObservationFactLinkedV1
      ]
    )
    expect(events.map(&:to_h).join).not_to include("captured_at", "recorded_at")
    expect(events.find { _1.is_a?(Coordinator::Write::Events::DevelopmentArtifactContentChangedV1) }.to_h)
      .to eq(artifact_id: artifact.artifact_id, content: "# Hello\n")
    expect(events.find { _1.is_a?(Coordinator::Write::Events::DevelopmentArtifactSourceChangedV1) }.to_h)
      .to eq(
        artifact_id: artifact.artifact_id,
        source_kind: "local_file",
        locator: "docs/hello.md",
        revision: "abc123",
        observed_at: "2026-09-03T12:00:00.000000Z"
      )

    links = events.drop(9)
    expect(links.map { _1.observed_fact.event_id }).to eq(decision.fact_event_ids)
    expect(links.map(&:artifact_id)).to all(eq(artifact.artifact_id))
    expect(links.map(&:role)).to eq(%w[created scope title kind source content label label])
  end
end
