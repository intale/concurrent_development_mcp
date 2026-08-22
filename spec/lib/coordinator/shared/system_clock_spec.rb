# frozen_string_literal: true

RSpec.describe Coordinator::Shared::SystemClock do
  it "returns the frozen domain timestamp representation" do
    expect(Coordinator::Shared::Types::TIMESTAMP_PATTERN).to match(described_class.new.now)
  end
end
