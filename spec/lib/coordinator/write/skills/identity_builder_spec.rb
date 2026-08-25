# frozen_string_literal: true

RSpec.describe Coordinator::Write::Skills::IdentityBuilder do
  subject(:builder) { described_class.new }

  it "derives stable identities from the exact name and scope tuple" do
    first = builder.call(name: "review", scope: "project:alpha")
    replay = builder.call(name: "review", scope: "project:alpha")
    other_scope = builder.call(name: "review", scope: "project:beta")

    expect(replay).to eq(first)
    expect(other_scope.skill_id).not_to eq(first.skill_id)
    expect(first).to have_attributes(name: "review", scope: "project:alpha")
  end
end
