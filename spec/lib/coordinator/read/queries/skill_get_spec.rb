# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::SkillGet, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:publisher) { Coordinator::Write::Operations::ExecutePublishSkillRevision.new(event_store:) }
  let(:projector) { Coordinator::Read::Projectors::SkillsV1.new }

  it "serves an observed revision even after the write side has advanced" do
    first_event = publish_and_fetch_event(command_id: "cmd-skill-get-1", expected_revision: 0)
    projector.call(first_event)
    publish_and_fetch_event(
      command_id: "cmd-skill-get-2",
      expected_revision: 1,
      instructions: "A newer unprojected revision."
    )

    result = query.call(name: "review", scope: "project:alpha").value!

    expect(result).to have_attributes(status: "ok")
    expect(result.data.skill).to have_attributes(
      revision: 1,
      instructions: "Inspect the complete diff."
    )
  end

  it "distinguishes exact scopes and returns typed invalid and absent results" do
    event = publish_and_fetch_event(command_id: "cmd-skill-work", expected_revision: 0, scope: "work")
    projector.call(event)

    available = query.call(name: "review", scope: "work").value!
    absent = query.call(name: "review", scope: "home").value!
    invalid = query.call(name: " review ", scope: "work").value!

    expect(available).to have_attributes(status: "ok")
    expect(absent).to have_attributes(status: "not_found")
    expect(absent.data).to have_attributes(code: "skill_not_observed")
    expect(invalid).to have_attributes(status: "invalid")
  end

  def publish_and_fetch_event(**overrides)
    input = {
      command_id: "cmd-skill-get-1",
      actor: { kind: "agent", id: "agent-1" },
      name: "review",
      scope: "project:alpha",
      expected_revision: 0,
      description: "Review a change",
      instructions: "Inspect the complete diff.",
      assets: []
    }.merge(overrides)
    result = publisher.call(input)
    expect(result).to be_success
    reference = result.value!.data.publication_event
    event_store.read_at(
      Coordinator::Write::StreamFactory.new.skill(result.value!.data.skill_id),
      reference.stream_revision
    )
  end
end
