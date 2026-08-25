# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::SkillList, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:publisher) { Coordinator::Write::Operations::ExecutePublishSkillRevision.new(event_store:) }
  let(:projector) { Coordinator::Read::Projectors::SkillsV1.new }

  it "pages by deterministic Skill ID and applies exact optional filters" do
    events = [
      publish(name: "review", scope: "work", command_id: "cmd-list-1"),
      publish(name: "review", scope: "home", command_id: "cmd-list-2"),
      publish(name: "deploy", scope: "work", command_id: "cmd-list-3")
    ]
    events.each { projector.call(_1) }

    first = query.call(limit: 2).value!.data.page
    expect(first).to have_attributes(has_more: true)
    expect(first.items.map(&:skill_id)).to eq(first.items.map(&:skill_id).sort)

    second = query.call(after_skill_id: first.next_skill_id, limit: 2).value!.data.page
    expect(second).to have_attributes(has_more: false, next_skill_id: nil)
    expect((first.items + second.items).map(&:skill_id)).to eq(
      Coordinator::Read::Skill.order(:skill_id).pluck(:skill_id)
    )

    work = query.call(scope: "work").value!.data.page
    review = query.call(name: "review").value!.data.page
    expect(work.items.map { [ _1.name, _1.scope ] }).to contain_exactly(
      [ "review", "work" ], [ "deploy", "work" ]
    )
    expect(review.items.map(&:scope)).to contain_exactly("home", "work")
  end

  it "returns a typed invalid result for a malformed cursor or limit" do
    result = query.call(after_skill_id: "skill-1", limit: 101).value!

    expect(result).to have_attributes(status: "invalid")
    expect(result.data).to have_attributes(code: "invalid_input")
  end

  def publish(name:, scope:, command_id:)
    result = publisher.call(
      command_id:,
      actor: { kind: "agent", id: "agent-1" },
      name:,
      scope:,
      expected_revision: 0,
      description: "#{name} in #{scope}",
      instructions: "Follow the scoped instructions.",
      assets: []
    )
    expect(result).to be_success
    reference = result.value!.data.publication_event
    event_store.read_at(
      Coordinator::Write::StreamFactory.new.skill(result.value!.data.skill_id),
      reference.stream_revision
    )
  end
end
