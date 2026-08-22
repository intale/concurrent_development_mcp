# frozen_string_literal: true

RSpec.describe Coordinator::Shared::IdGenerator do
  it "uses the installed Ruby UUIDv7 facility" do
    expect(Coordinator::Shared::Types::UUID_V7_PATTERN).to match(described_class.new.uuid_v7)
  end
end
