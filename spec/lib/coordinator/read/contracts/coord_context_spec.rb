# frozen_string_literal: true

RSpec.describe Coordinator::Read::Contracts::CoordContext do
  subject(:contract) { described_class.new }

  it "accepts exactly one scope root and an observed-view cache token" do
    result = contract.call(
      attempt_id: "A-100",
      context_token: "sha256:#{'a' * 64}"
    )

    expect(result).to be_success
    expect(result.to_h).to eq(
      attempt_id: "A-100",
      context_token: "sha256:#{'a' * 64}"
    )
  end

  it "rejects absent, ambiguous, and malformed scope input" do
    expect(contract.call({}).errors.to_h).to include(:change_set_id)
    expect(contract.call(change_set_id: "CS-100", work_item_id: "W-100").errors.to_h).to include(:change_set_id)
    expect(contract.call(work_item_id: "bad id").errors.to_h).to include(:work_item_id)
    expect(contract.call(change_set_id: "CS-100", after_command_id: "cmd-100").errors.to_h).to include(:after_command_id)
  end
end
