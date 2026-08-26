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
end
