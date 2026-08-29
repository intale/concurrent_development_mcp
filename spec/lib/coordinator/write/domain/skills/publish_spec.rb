# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::Skills::Publish do
  subject(:decider) { described_class.new }

  let(:published_at) { "2026-08-25T09:30:00.000000Z" }
  let(:command) { build_command }

  it "given an absent tuple and expected revision zero, emits revision one" do
    result = decider.call(
      state: Coordinator::Write::Domain::Skills::State.initial,
      command:,
      published_at:
    )

    expect(result).to be_success
    write = result.value!.writes.sole
    expect(write.stream.to_h).to eq(
      context: "AgentKnowledge",
      stream_name: "Skill",
      stream_id: command.skill_id
    )
    expect(write.event).to have_attributes(
      skill_id: command.skill_id,
      name: "review",
      scope: "project:alpha",
      revision: 1,
      published_at:
    )
    expect(write.event).to be_a(Coordinator::Write::Events::SkillRevisionPublishedV2)
  end

  it "given revision one and expected revision one, emits revision two" do
    state = Coordinator::Write::Domain::Skills::State.reduce([ publication(revision: 1) ])

    result = decider.call(state:, command: build_command(expected_revision: 1), published_at:)

    expect(result).to be_success
    expect(result.value!.events.sole.revision).to eq(2)
  end

  it "denies a stale expected revision without producing events" do
    state = Coordinator::Write::Domain::Skills::State.reduce([ publication(revision: 2) ])

    result = decider.call(state:, command: build_command(expected_revision: 1), published_at:)

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :skill_revision_conflict,
      details: include(expected_revision: 1, current_revision: 2)
    )
  end

  def build_command(expected_revision: 0)
    identity = Coordinator::Write::Skills::IdentityBuilder.new.call(
      name: "review",
      scope: "project:alpha"
    )
    content = Coordinator::Write::Skills::RevisionBuilder.new.call(
      identity:,
      description: "Review changes",
      instructions: "Inspect the entire diff.",
      assets: []
    ).value!
    Coordinator::Write::Commands::PublishSkillRevision.new(
      command_id: "cmd-skill-#{expected_revision}",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-1"),
      skill_id: identity.skill_id,
      name: identity.name,
      scope: identity.scope,
      expected_revision:,
      description: content.description,
      instructions: content.instructions,
      assets: content.assets,
      content_digest: content.content_digest
    )
  end

  def publication(revision:)
    Coordinator::Write::Events::SkillRevisionPublishedV2.new(
      skill_id: command.skill_id,
      name: command.name,
      scope: command.scope,
      revision:,
      description: command.description,
      instructions: command.instructions,
      assets: command.assets,
      content_digest: command.content_digest,
      published_at:
    )
  end
end
