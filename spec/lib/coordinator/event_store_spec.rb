# frozen_string_literal: true

RSpec.describe Coordinator::EventStore, :event_store do
  subject(:event_store) { described_class.new(client: PgEventstore.client) }

  let(:stream) { Coordinator::StreamFactory.new.change_set("CS-real-store") }
  let(:probe_read) do
    Coordinator::EventReadCriteria.new(
      event_types: [ "RealStoreProbe" ],
      maximum_count: 1,
      direction: :asc
    )
  end
  let(:event) { build_event(type: "RealStoreProbe", data: { "probe" => true }) }

  def build_event(type:, data: {})
    PgEventstore::Event.new(
      id: Coordinator::IdGenerator.new.uuid_v7,
      type:,
      data:,
      metadata: { "schema_version" => 1 }
    )
  end

  it "reads only the requested event types within an explicit real-store bound" do
    event_store.append(stream, [ build_event(type: "IgnoredProbe"), event ])

    expect(event_store.read(stream, probe_read)).to contain_exactly(
      have_attributes(id: event.id, type: "RealStoreProbe", stream_revision: 1)
    )
  end

  it "raises instead of returning a silently truncated real history" do
    event_store.append(stream, [ event, build_event(type: "RealStoreProbe") ])

    expect { event_store.read(stream, probe_read) }
      .to raise_error(Coordinator::EventHistoryLimitExceeded, /exceeded 1 relevant events/)
  end

  it "reads the latest real event of each requested type with read_grouped" do
    newest_probe = build_event(type: "RealStoreProbe", data: { "version" => 2 })
    event_store.append(
      stream,
      [
        build_event(type: "RealStoreProbe", data: { "version" => 1 }),
        build_event(type: "OtherProbe", data: { "version" => 1 }),
        newest_probe
      ]
    )
    criteria = Coordinator::GroupedEventReadCriteria.new(
      event_types: [ "RealStoreProbe", "OtherProbe" ],
      direction: :desc
    )

    grouped = event_store.read_grouped(stream, criteria).to_h { [ _1.type, _1 ] }

    expect(grouped.fetch("RealStoreProbe").id).to eq(newest_probe.id)
    expect(grouped.fetch("OtherProbe").data).to eq("version" => 1)
  end

  it "commits all real requests in one multiple transaction" do
    result = event_store.multiple do
      event_store.append(stream, [ event ])
      :committed
    end

    expect(result).to eq(:committed)
    expect(event_store.read(stream, probe_read).map(&:id)).to eq([ event.id ])
  end

  it "rolls back real requests when the multiple transaction raises" do
    expect do
      event_store.multiple do
        event_store.append(stream, [ event ])
        raise "rollback probe"
      end
    end.to raise_error("rollback probe")

    expect(event_store.read(stream, probe_read)).to be_empty
  end
end
