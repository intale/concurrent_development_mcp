# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Observability::InFlight do
  it "tracks overlapping invocations independently within each bounded label tuple" do
    tracker = described_class.new
    labels = { "event.type" => "One" }.freeze
    other = { "event.type" => "Two" }.freeze
    first = tracker.enter(labels)
    second = tracker.enter(labels)
    third = tracker.enter(other)
    expect(tracker.oldest_age(labels)).to be > 0
    tracker.leave(labels, first)
    expect(tracker.oldest_age(labels)).to be > 0
    tracker.leave(labels, second)
    expect(tracker.oldest_age(labels)).to eq(0.0)
    expect(tracker.oldest_age(other)).to be > 0
    tracker.leave(other, third)
    expect(tracker.oldest_age(other)).to eq(0.0)
  end
end
