# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::SkillsV1, :event_store, :read_model do
  subject(:projector) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:publisher) { Coordinator::Write::Operations::ExecutePublishSkillRevision.new(event_store:) }
  let(:repository) { Coordinator::Read::Repositories::Skills.new }

  it "projects immutable revisions idempotently with exact source evidence" do
    publish(input)
    first_event = skill_events.sole
    projector.call(first_event)
    projector.call(first_event)

    first = repository.fetch(name: "review", scope: "project:alpha")
    expect(first).to have_attributes(
      revision: 1,
      instructions: "Inspect the complete diff.",
      published: have_attributes(
        event: have_attributes(event_id: first_event.id, stream_revision: 0),
        global_position: first_event.global_position,
        causation_id: first_event.causation_id,
        correlation_id: first_event.correlation_id
      )
    )
    expect(first.assets.map(&:path)).to eq([ "scripts/check.sh" ])

    publish(
      input(
        command_id: "cmd-skill-2",
        expected_revision: 1,
        instructions: "Inspect behavior and contracts.",
        assets: [ asset(path: "fixtures/example.json", content: "{}") ]
      )
    )
    second_event = skill_events.last

    available_before_projection = repository.fetch(name: "review", scope: "project:alpha")
    expect(available_before_projection).to have_attributes(revision: 1)

    projector.call(second_event)
    projector.call(second_event)
    current = repository.fetch(name: "review", scope: "project:alpha")
    historical = repository.fetch(name: "review", scope: "project:alpha", revision: 1)
    expect(current).to have_attributes(revision: 2, instructions: "Inspect behavior and contracts.")
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
    publish(input)
    publish(input(command_id: "cmd-skill-2", expected_revision: 1, instructions: "Newest."))
    first_event, second_event = skill_events

    projector.call(second_event)
    projector.call(first_event)

    current = repository.fetch(name: "review", scope: "project:alpha")
    historical = repository.fetch(name: "review", scope: "project:alpha", revision: 1)
    expect(current).to have_attributes(revision: 2, instructions: "Newest.")
    expect(historical).to have_attributes(revision: 1, instructions: "Inspect the complete diff.")
    expect(processed_events.count).to eq(2)
  end

  def publish(attributes)
    result = publisher.call(attributes)
    expect(result).to be_success
    result
  end

  def input(**overrides)
    {
      command_id: "cmd-skill-1",
      actor: { kind: "agent", id: "agent-1" },
      name: "review",
      scope: "project:alpha",
      expected_revision: 0,
      description: "Review a change",
      instructions: "Inspect the complete diff.",
      assets: [ asset(path: "scripts/check.sh", content: "#!/bin/sh\nexit 0\n") ]
    }.merge(overrides)
  end

  def asset(path:, content:)
    {
      path:,
      media_type: "application/octet-stream",
      executable: false,
      content_base64: [ content ].pack("m0")
    }
  end

  def skill_events
    identity = Coordinator::Write::Skills::IdentityBuilder.new.call(
      name: "review",
      scope: "project:alpha"
    )
    event_store.read(
      Coordinator::Write::StreamFactory.new.skill(identity.skill_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "SkillRevisionPublished" ],
        maximum_count: 100,
        direction: :asc
      )
    )
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "skills",
      projection_version: 2
    )
  end
end
