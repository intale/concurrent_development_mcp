# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::SkillGet, :read_model do
  subject(:query) { described_class.new }

  it "serves the latest available projected revision" do
    skill = create(
      :coordinator_read_skill,
      name: "review",
      scope: "project:alpha",
      revision: 1
    )
    create(
      :coordinator_read_skill_revision,
      skill:,
      revision: 1,
      instructions: "Inspect the complete diff."
    )

    result = query.call(name: "review", scope: "project:alpha").value!

    expect(result).to have_attributes(status: "ok")
    expect(result.data.skill).to have_attributes(
      revision: 1,
      instructions: "Inspect the complete diff."
    )
  end

  it "distinguishes exact scopes and returns typed invalid and absent results" do
    skill = create(:coordinator_read_skill, name: "review", scope: "work")
    create(:coordinator_read_skill_revision, skill:)

    available = query.call(name: "review", scope: "work").value!
    absent = query.call(name: "review", scope: "home").value!
    invalid = query.call(name: " review ", scope: "work").value!

    expect(available).to have_attributes(status: "ok")
    expect(absent).to have_attributes(status: "not_found")
    expect(absent.data).to have_attributes(code: "skill_not_observed")
    expect(invalid).to have_attributes(status: "invalid")
  end

  it "retrieves an immutable historical revision after the projected head advances" do
    skill = create(
      :coordinator_read_skill,
      name: "review",
      scope: "project:alpha",
      revision: 2
    )
    create(
      :coordinator_read_skill_revision,
      skill:,
      revision: 1,
      instructions: "Inspect the complete diff."
    )
    create(:coordinator_read_skill_revision, skill:, revision: 2, instructions: "Revision two.")

    historical = query.call(name: "review", scope: "project:alpha", revision: 1).value!
    absent = query.call(name: "review", scope: "project:alpha", revision: 3).value!

    expect(historical).to have_attributes(status: "ok")
    expect(historical.data.skill).to have_attributes(
      revision: 1,
      instructions: "Inspect the complete diff."
    )
    expect(absent).to have_attributes(status: "not_found")
    expect(absent.data.details).to include(revision: 3)
  end
end
