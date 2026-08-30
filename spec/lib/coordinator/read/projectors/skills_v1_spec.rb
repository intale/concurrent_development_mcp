# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::SkillsV1, :read_model do
  subject(:projector) { described_class.new }

  let(:repository) { Coordinator::Read::Repositories::Skills.new }
  let(:identity) do
    Coordinator::Write::Skills::IdentityBuilder.new.call(name: "review", scope: "project:alpha")
  end

  it "projects concrete immutable revisions idempotently with exact source evidence" do
    first_event = publication_event(
      revision: 1,
      instructions: "Inspect the complete diff.",
      path: "scripts/check.sh",
      content: "#!/bin/sh\nexit 0\n"
    )
    second_event = publication_event(
      revision: 2,
      instructions: "Inspect behavior and contracts.",
      path: "fixtures/example.json",
      content: "{}"
    )

    projector.call(first_event)
    projector.call(first_event)
    available = repository.fetch(name: "review", scope: "project:alpha")
    expect(available).to have_attributes(revision: 1, instructions: "Inspect the complete diff.")

    projector.call(second_event)
    projector.call(second_event)

    current = repository.fetch(name: "review", scope: "project:alpha")
    historical = repository.fetch(name: "review", scope: "project:alpha", revision: 1)
    expect(current).to have_attributes(
      revision: 2,
      instructions: "Inspect behavior and contracts.",
      published: have_attributes(
        event: have_attributes(event_id: second_event.id, stream_revision: 1),
        global_position: second_event.global_position,
        causation_id: second_event.causation_id,
        correlation_id: second_event.correlation_id
      )
    )
    expect(current.assets.map(&:path)).to eq([ "fixtures/example.json" ])
    expect(historical).to have_attributes(revision: 1, instructions: "Inspect the complete diff.")
    expect(historical.assets.map(&:path)).to eq([ "scripts/check.sh" ])
    expect(Coordinator::Read::Skill.count).to eq(1)
    expect(Coordinator::Read::SkillRevision.count).to eq(2)
    expect(Coordinator::Read::SkillAsset.count).to eq(2)
    expect(processed_events.count).to eq(2)
    expect(current.to_h.keys & %i[fresh pending projection_status]).to be_empty
  end

  it "accepts a newer full snapshot first and never regresses on delayed older delivery" do
    first_event = publication_event(
      revision: 1,
      instructions: "Inspect the complete diff.",
      path: "scripts/check.sh",
      content: "#!/bin/sh\nexit 0\n"
    )
    second_event = publication_event(
      revision: 2,
      instructions: "Newest.",
      path: "fixtures/example.json",
      content: "{}"
    )

    projector.call(second_event)
    projector.call(first_event)

    current = repository.fetch(name: "review", scope: "project:alpha")
    historical = repository.fetch(name: "review", scope: "project:alpha", revision: 1)
    expect(current).to have_attributes(revision: 2, instructions: "Newest.")
    expect(historical).to have_attributes(revision: 1, instructions: "Inspect the complete diff.")
    expect(processed_events.count).to eq(2)
  end

  def publication_event(revision:, instructions:, path:, content:)
    asset_input = {
      path:,
      executable: false,
      content: {
        encoding: "utf-8",
        media_type: "text/plain",
        text: content
      }
    }
    revision_content = Coordinator::Write::Skills::RevisionBuilder.new.call(
      identity:,
      description: "Review a change",
      instructions:,
      assets: [ asset_input ]
    ).value!
    payload = Coordinator::Write::Events::SkillRevisionPublishedV2.new(
      skill_id: identity.skill_id,
      name: identity.name,
      scope: identity.scope,
      revision:,
      description: revision_content.description,
      instructions: revision_content.instructions,
      assets: revision_content.assets,
      content_digest: revision_content.content_digest,
      published_at: "2026-08-30T12:0#{revision}:00.000000Z"
    )
    ProjectionEventFactory.build(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.skill(identity.skill_id),
      stream_revision: revision - 1,
      global_position: 100 * revision,
      command_id: "cmd-skill-#{revision}",
      policy_version: "skill-repository/v1",
      actor_id: "agent-1",
      markers: [ "skill:#{identity.skill_id}" ]
    )
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "skills",
      projection_version: 3
    )
  end
end
