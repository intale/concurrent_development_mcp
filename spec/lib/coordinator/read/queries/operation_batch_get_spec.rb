# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::OperationBatchGet, :read_model do
  subject(:query) { described_class.new }

  it "returns not found and validation outcomes without consulting the write side" do
    missing = query.call(batch_id: SecureRandom.uuid_v7)
    invalid = query.call(batch_id: "not-a-batch")

    expect(missing.value!).to have_attributes(status: "not_found")
    expect(invalid.value!).to have_attributes(status: "invalid")
  end
end
