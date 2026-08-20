# frozen_string_literal: true

RSpec.describe Coordinator::EventStore do
  let(:client) { instance_double(PgEventstore::Client) }
  let(:stream_reference) { Coordinator::StreamFactory.new.change_set("CS-100") }
  let(:pg_stream) do
    PgEventstore::Stream.new(
      context: "DevelopmentPlanning",
      stream_name: "ChangeSet",
      stream_id: "CS-100"
    )
  end
  subject(:event_store) { described_class.new(client:) }

  it "folds every public paginated-read batch in ascending order" do
    first = PgEventstore::Event.new(type: "First")
    second = PgEventstore::Event.new(type: "Second")
    allow(client).to receive(:read_paginated)
      .with(pg_stream, options: { direction: :asc })
      .and_return([ [ first ], [ second ] ].each)

    expect(event_store.read_all(stream_reference)).to eq([ first, second ])
  end

  it "maps append and multiple through public client APIs" do
    event = PgEventstore::Event.new(type: "ChangeSetCreated")
    allow(client).to receive(:append_to_stream).with(pg_stream, [ event ]).and_return([ event ])
    allow(client).to receive(:multiple).and_yield.and_return(:transaction_result)

    expect(event_store.append(stream_reference, [ event ])).to eq([ event ])
    expect(event_store.multiple { :block_result }).to eq(:transaction_result)
  end
end
