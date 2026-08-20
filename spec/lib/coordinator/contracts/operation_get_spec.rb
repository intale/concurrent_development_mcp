# frozen_string_literal: true

RSpec.describe Coordinator::Contracts::OperationGet do
  subject(:contract) { described_class.new }

  it "accepts a bounded known projection selection" do
    expect(
      contract.call(command_id: "cmd-100", projections: [ "coord_context_v1" ])
    ).to be_success
  end

  it "rejects invalid command IDs and unknown or duplicate projections" do
    expect(contract.call(command_id: "bad id").errors.to_h).to include(:command_id)
    expect(
      contract.call(command_id: "cmd-100", projections: [ "other" ]).errors.to_h
    ).to include(:projections)
    expect(
      contract.call(
        command_id: "cmd-100",
        projections: [ "coord_context_v1", "coord_context_v1" ]
      ).errors.to_h
    ).to include(:projections)
  end
end
