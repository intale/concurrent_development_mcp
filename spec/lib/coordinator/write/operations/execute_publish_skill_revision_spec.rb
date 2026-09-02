# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecutePublishSkillRevision, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:marker_builder) { Coordinator::Write::Skills::MarkerBuilder.new }

  it "atomically publishes a complete immutable revision and its command completion" do
    result = operation.call(input)

    expect(result).to be_success
    receipt = result.value!.data
    expect(receipt).to have_attributes(
      name: "review",
      scope: "project:alpha",
      revision: 1,
      asset_count: 1
    )
    event = skill_events("review", "project:alpha").sole
    expect(event).to have_attributes(type: "SkillRevisionPublished", stream_revision: 0)
    expect(event.markers).to include("command:cmd-skill-1")
    persisted_asset = event.data.fetch("assets").sole
    expect(persisted_asset).to include("path" => "scripts/check.sh")
    expect(persisted_asset.fetch("content")).to include(
      "encoding" => "utf-8",
      "text" => "#!/bin/sh\nexit 0\n",
      "content_sha256" => a_string_matching(/\Asha256:[0-9a-f]{64}\z/),
      "byte_size" => 17
    )
    expect(persisted_asset.fetch("content")).not_to have_key("base64")
    expect(command_events("cmd-skill-1").map(&:type)).to eq([ "CommandCompleted" ])
  end

  it "replays an identical command and rejects changed command reuse" do
    original = operation.call(input)
    event_ids = skill_events("review", "project:alpha").map(&:id)

    replay = operation.call(input)
    changed = operation.call(input.merge(instructions: "Use a different process."))

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(changed.failure.code).to eq(:command_id_reused)
    expect(skill_events("review", "project:alpha").map(&:id)).to eq(event_ids)
  end

  it "advances only from the exact authoritative revision" do
    first = operation.call(input)
    second = operation.call(
      input.merge(command_id: "cmd-skill-2", expected_revision: 1, instructions: "Review tests too.")
    )
    stale = operation.call(
      input.merge(command_id: "cmd-skill-stale", expected_revision: 1, instructions: "Stale edit.")
    )

    expect([ first, second ]).to all(be_success)
    expect(second.value!.data.revision).to eq(2)
    expect(stale.failure.code).to eq(:skill_revision_conflict)
    expect(skill_events("review", "project:alpha").map(&:stream_revision)).to eq([ 0, 1 ])
    expect(command_events("cmd-skill-stale")).to be_empty
  end

  it "treats equal names under different exact scopes as independent skills" do
    home = operation.call(input(scope: "home"))
    work = operation.call(input(command_id: "cmd-skill-work", scope: "work"))

    expect([ home, work ]).to all(be_success)
    expect(home.value!.data.skill_id).not_to eq(work.value!.data.skill_id)
    expect(skill_events("review", "home").length).to eq(1)
    expect(skill_events("review", "work").length).to eq(1)
  end

  it "serializes competing publications of the same expected revision" do
    contenders = [
      input,
      input(command_id: "cmd-skill-race", instructions: "Competing instructions.")
    ]

    results = contenders.map do |candidate|
      Thread.new { described_class.new(event_store:).call(candidate) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:skill_revision_conflict)
    expect(skill_events("review", "project:alpha").length).to eq(1)
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
      assets: [
        {
          path: "scripts/check.sh",
          executable: true,
          content: {
            encoding: "utf-8",
            media_type: "text/x-shellscript",
            text: "#!/bin/sh\nexit 0\n"
          }
        }
      ]
    }.merge(overrides)
  end

  def skill_events(name, scope)
    registration = event_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "AgentKnowledge",
        stream_name: "Skill",
        event_types: [ "SkillRevisionPublished" ],
        markers: [ marker_builder.natural_key(name:, scope:) ],
        maximum_count: 1,
        direction: :asc
      )
    ).first
    return [] unless registration

    event_store.read(
      streams.skill(registration.stream.stream_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "SkillRevisionPublished" ],
        maximum_count: 100,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
end
