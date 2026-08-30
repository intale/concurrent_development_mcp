# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::SkillList, :read_model do
  subject(:query) { described_class.new }

  SKILL_IDS = %w[
    skill:v1:0000000000000000000000000000000000000000000000000000000000000021
    skill:v1:0000000000000000000000000000000000000000000000000000000000000022
    skill:v1:0000000000000000000000000000000000000000000000000000000000000023
  ].freeze

  it "pages by deterministic Skill ID and applies exact optional filters" do
    [
      [ "review", "work" ],
      [ "review", "home" ],
      [ "deploy", "work" ]
    ].each_with_index do |(name, scope), index|
      skill = create(
        :coordinator_read_skill,
        skill_id: SKILL_IDS.fetch(index),
        name:,
        scope:
      )
      create(:coordinator_read_skill_revision, skill:, description: "#{name} in #{scope}")
    end

    first = query.call(limit: 2).value!.data.page
    expect(first).to have_attributes(has_more: true)
    expect(first.items.map(&:skill_id)).to eq(SKILL_IDS.first(2))

    second = query.call(after_skill_id: first.next_skill_id, limit: 2).value!.data.page
    expect(second).to have_attributes(has_more: false, next_skill_id: nil)
    expect((first.items + second.items).map(&:skill_id)).to eq(SKILL_IDS)

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
end
