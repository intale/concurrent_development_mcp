# frozen_string_literal: true

RSpec.describe Coordinator::Contracts::PersistedEvents do
  subject(:contract) { described_class.new }

  let(:persisted_event) do
    PgEventstore::Event.new(
      stream: PgEventstore::Stream.new(
        context: "DevelopmentPlanning",
        stream_name: "ChangeSet",
        stream_id: "CS-100"
      ),
      stream_revision: 0
    )
  end

  it "accepts a nonempty collection of persisted event references" do
    result = contract.call(events: [ persisted_event ])

    expect(result).to be_success
    expect(result.to_h.fetch(:events)).to eq([ persisted_event ])
  end

  it "rejects empty and not-yet-persisted event collections" do
    empty = contract.call(events: [])
    transient = contract.call(events: [ PgEventstore::Event.new ])

    expect(empty).to be_failure
    expect(empty.errors.to_h).to have_key(:events)
    expect(transient).to be_failure
    expect(transient.errors.to_h).to have_key(:events)
  end
end
