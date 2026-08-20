# frozen_string_literal: true

RSpec.describe Coordinator::SystemClock do
  it "returns the frozen domain timestamp representation" do
    expect(Coordinator::Types::TIMESTAMP_PATTERN).to match(described_class.new.now)
  end
end
