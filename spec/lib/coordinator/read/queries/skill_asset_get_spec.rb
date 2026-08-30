# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::SkillAssetGet, :read_model do
  subject(:query) { described_class.new }

  it "returns one passive binary asset from the current projected revision" do
    skill = create(
      :coordinator_read_skill,
      name: "binary-helper",
      scope: "project:alpha"
    )
    create(:coordinator_read_skill_revision, skill:, asset_count: 1)
    create(
      :coordinator_read_skill_asset,
      :binary,
      skill:,
      path: "fixtures/input.bin",
      content_base64: "AAFza2lsbP8=",
      byte_size: 8
    )

    available = query.call(
      name: "binary-helper",
      scope: "project:alpha",
      path: "fixtures/input.bin"
    ).value!
    missing = query.call(
      name: "binary-helper",
      scope: "project:alpha",
      path: "fixtures/missing.bin"
    ).value!

    expect(available).to have_attributes(status: "ok")
    expect(available.data.asset).to have_attributes(
      revision: 1,
      encoding: "binary",
      base64: "AAFza2lsbP8=",
      byte_size: 8,
      executable: false
    )
    expect(available.warnings).to include(a_string_matching(/does not inspect or execute/))
    expect(missing).to have_attributes(status: "not_found")
  end

  it "pins asset content to the requested historical revision" do
    skill = create(
      :coordinator_read_skill,
      name: "binary-helper",
      scope: "project:alpha",
      revision: 2
    )
    create(:coordinator_read_skill_revision, skill:, revision: 1, asset_count: 1)
    create(:coordinator_read_skill_revision, skill:, revision: 2, asset_count: 1)
    create(
      :coordinator_read_skill_asset,
      :binary,
      skill:,
      revision: 1,
      path: "fixtures/input.bin",
      content_base64: "b25l",
      byte_size: 3
    )
    create(
      :coordinator_read_skill_asset,
      :binary,
      skill:,
      revision: 2,
      path: "fixtures/input.bin",
      content_base64: "dHdv",
      byte_size: 3
    )

    historical = query.call(
      name: "binary-helper",
      scope: "project:alpha",
      path: "fixtures/input.bin",
      revision: 1
    ).value!

    expect(historical).to have_attributes(status: "ok")
    expect(historical.data.asset).to have_attributes(revision: 1, base64: "b25l")
  end
end
