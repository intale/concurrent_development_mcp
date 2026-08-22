# frozen_string_literal: true

RSpec.describe Coordinator::Read::Contracts::OperationGet do
  subject(:contract) { described_class.new }

  it "accepts a projected receipt identity" do
    expect(contract.call(command_id: "cmd-100")).to be_success
  end

  it "rejects invalid command IDs and obsolete freshness selections" do
    expect(contract.call(command_id: "bad id").errors.to_h).to include(:command_id)
    expect(
      contract.call(command_id: "cmd-100", projections: [ "coord_context_v1" ]).errors.to_h
    ).to include(:projections)
  end
end
