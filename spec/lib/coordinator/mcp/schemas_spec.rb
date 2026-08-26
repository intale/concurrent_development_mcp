# frozen_string_literal: true

RSpec.describe Coordinator::Mcp::Schemas do
  it "advertises the same Candidate and write-set resource boundary" do
    write_set_maximum = described_class.write_set_reserve
      .dig(:properties, :resources, :maxItems)
    candidate_maximum = described_class.candidate_submit
      .dig(:properties, :change_manifest, :properties, :files, :maxItems)

    expect(candidate_maximum).to eq(write_set_maximum)
    expect(candidate_maximum).to eq(Coordinator::Shared::Types::WRITE_SET_RESOURCE_MAXIMUM_COUNT)
  end

  it "requires one exact scope and bounds the Repository discovery cursor" do
    schema = described_class.repository_list

    expect(schema.fetch(:required)).to eq([ "scope" ])
    expect(schema.dig(:properties, :scope)).to include(
      type: "string",
      minLength: 1,
      maxLength: 500
    )
    expect(schema.dig(:properties, :after_repository_id, :anyOf).first).to include(
      type: "string",
      pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
    )
    expect(schema.dig(:properties, :limit, :anyOf).first).to include(
      type: "integer",
      minimum: 1,
      maximum: 100
    )
  end

  it "lets Skill and Skill-asset reads pin one immutable projected revision" do
    [ described_class.skill_get, described_class.skill_asset_get ].each do |schema|
      expect(schema.dig(:properties, :revision, :anyOf).first).to include(
        type: "integer",
        minimum: 1
      )
      expect(schema.fetch(:required)).not_to include("revision")
    end
  end
end
