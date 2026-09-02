# frozen_string_literal: true

RSpec.describe Coordinator::Write::Skills::IdentityBuilder do
  subject(:builder) { described_class.new }

  it "allocates UUIDv7 identities while preserving the supplied natural tuple" do
    first = builder.call(name: "review", scope: "project:alpha")
    replay = builder.call(name: "review", scope: "project:alpha")
    other_scope = builder.call(name: "review", scope: "project:beta")

    expect(replay.skill_id).not_to eq(first.skill_id)
    expect(other_scope.skill_id).not_to eq(first.skill_id)
    expect([ first.skill_id, replay.skill_id, other_scope.skill_id ]).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(first).to have_attributes(name: "review", scope: "project:alpha")
  end
end
