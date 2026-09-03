# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecutePublishSkillRevision, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:marker_builder) { Coordinator::Write::Skills::MarkerBuilder.new }

  it "atomically publishes cohesive facts across Skill, revision, and asset streams" do
    result = operation.call(input)

    expect(result).to be_success
    receipt = result.value!.data
    expect(receipt).to have_attributes(
      name: "review",
      scope: "project:alpha",
      revision: 1,
      asset_count: 1
    )
    events = skill_revision_events("review", "project:alpha")
    expect(events.map(&:type)).to eq(%w[
      SkillRegistered
      SkillRevisionCreated
      SkillRevisionDescriptionDefined
      SkillRevisionInstructionsDefined
      SkillAssetCreated
      SkillAssetPathDefined
      SkillAssetContentDefined
      SkillAssetExecutabilityDefined
      SkillAssetAddedToRevision
      SkillRevisionPublished
    ])
    expect(events).to all(satisfy { _1.markers.include?("command:cmd-skill-1") })
    content = events.find { _1.type == "SkillAssetContentDefined" }
    expect(content.data).to include("content" => "#!/bin/sh\nexit 0\n")
    expect(content.data.keys).to contain_exactly("asset_id", "content")
    expect(content.metadata).to include(
      "encoding" => "utf-8",
      "media_type" => "text/x-shellscript",
      "content_sha256" => a_string_matching(/\Asha256:[0-9a-f]{64}\z/),
      "byte_size" => 17
    )
    publication = events.last
    expect(publication.data.keys).to contain_exactly("skill_id", "skill_revision_id", "revision")
    expect(publication.metadata).to include("content_digest" => receipt.content_digest)
    expect(command_events("cmd-skill-1")).to be_empty
  end

  it "leaves replay ownership to the registered Command lifecycle" do
    expect(operation.call(input)).to be_success
    event_ids = skill_revision_events("review", "project:alpha").map(&:id)

    replay = operation.call(input)
    changed = operation.call(input.merge(instructions: "Use a different process."))

    expect(replay.failure.code).to eq(:skill_revision_conflict)
    expect(changed.failure.code).to eq(:skill_revision_conflict)
    expect(skill_revision_events("review", "project:alpha").map(&:id)).to eq(event_ids)
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
    expect(skill_events("review", "project:alpha").select { _1.type == "SkillRevisionPublished" }.map(&:stream_revision))
      .to eq([ 1, 2 ])
    expect(command_events("cmd-skill-stale")).to be_empty
  end

  it "returns the current publication without emitting a content-identical revision" do
    first = operation.call(input)
    event_ids = skill_revision_events("review", "project:alpha").map(&:id)

    existing = operation.call(input(command_id: "cmd-skill-existing", expected_revision: 1))

    expect([ first, existing ]).to all(be_success)
    expect(existing.value!.data.revision).to eq(1)
    expect(existing.value!.emitted_events).to be_empty
    expect(skill_revision_events("review", "project:alpha").map(&:id)).to eq(event_ids)
  end

  it "treats equal names under different exact scopes as independent skills" do
    home = operation.call(input(scope: "home"))
    work = operation.call(input(command_id: "cmd-skill-work", scope: "work"))

    expect([ home, work ]).to all(be_success)
    expect(home.value!.data.skill_id).not_to eq(work.value!.data.skill_id)
    expect(skill_events("review", "home").count { _1.type == "SkillRevisionPublished" }).to eq(1)
    expect(skill_events("review", "work").count { _1.type == "SkillRevisionPublished" }).to eq(1)
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
    expect(skill_events("review", "project:alpha").count { _1.type == "SkillRevisionPublished" }).to eq(1)
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
        event_types: [ "SkillRegistered" ],
        markers: [ marker_builder.natural_key(name:, scope:) ],
        maximum_count: 1,
        direction: :asc
      )
    ).first
    return [] unless registration

    event_store.read(
      streams.skill(registration.stream.stream_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "SkillRegistered", "SkillRevisionPublished" ],
        maximum_count: 100,
        direction: :asc
      )
    )
  end

  def skill_revision_events(name, scope)
    skill = skill_events(name, scope)
    publication = skill.reverse.find { _1.type == "SkillRevisionPublished" }
    revision_id = publication.data.fetch("skill_revision_id")
    revision = event_store.read(
      streams.skill_revision(revision_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          SkillRevisionCreated
          SkillRevisionDescriptionDefined
          SkillRevisionInstructionsDefined
          SkillAssetAddedToRevision
        ],
        maximum_count: 100,
        direction: :asc
      )
    )
    assets = revision.select { _1.type == "SkillAssetAddedToRevision" }.flat_map do |assignment|
      event_store.read(
        streams.skill_asset(assignment.data.fetch("asset_id")),
        Coordinator::Write::EventReadCriteria.new(
          event_types: %w[
            SkillAssetCreated
            SkillAssetPathDefined
            SkillAssetContentDefined
            SkillAssetExecutabilityDefined
          ],
          maximum_count: 4,
          direction: :asc
        )
      )
    end
    (skill + revision + assets).sort_by(&:global_position)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end
end
