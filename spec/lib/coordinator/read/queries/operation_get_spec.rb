# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::OperationGet, :read_model do
  subject(:query) { described_class.new }

  it "serves the latest available receipt projection without a write-store fallback" do
    expect(query.call(command_id: "cmd-100").value!.status).to eq("not_found")

    receipt = create(:coordinator_read_command_receipt, command_id: "cmd-100")
    observed = query.call(command_id: "cmd-100").value!

    expect(observed.status).to eq("ok")
    expect(observed.data.result.to_h).to eq(change_set_id: "CS-cmd-100")
    expect(observed.data.emitted_events.map(&:type)).to eq([ "ChangeSetCreated" ])
    expect(observed.receipt).to eq(receipt.receipt)
    expect(observed.to_h).not_to include(:projection_status)
  end

  it "does not depend on unrelated coordination projections" do
    create(:coordinator_read_command_receipt, command_id: "cmd-200")

    expect(query.call(command_id: "cmd-200").value!.status).to eq("ok")
    expect(Coordinator::Read::CoordContext.count).to eq(0)
  end

  it "returns not_found and typed invalid input" do
    expect(query.call(command_id: "cmd-404").value!.status).to eq("not_found")
    expect(query.call(command_id: "bad id").value!.status).to eq("invalid")
  end
end
