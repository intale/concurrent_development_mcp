# frozen_string_literal: true

RSpec.describe Coordinator::Write::NaturalKeys::Registry, :event_store do
  subject(:registry) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:id_generator) { Coordinator::Shared::IdGenerator.new }
  let(:marker_codec) { Coordinator::Shared::Markers::CodecV2.new }

  def selector(marker)
    described_class::SelectorV1.new(
      stream_context: "RegistryProbe",
      stream_name: "Identity",
      event_type: "NaturalKeyRegisteredProbe",
      marker:
    )
  end

  def marker_for(value)
    marker_codec.call(
      purpose: "registry-probe",
      components: [ { dimension: "value", value: } ]
    ).value!.marker
  end

  def registration(value, marker: marker_for(value))
    identity = id_generator.uuid_v7
    event_id = id_generator.uuid_v7
    stream = Coordinator::Write::StreamReference.new(
      context: "RegistryProbe",
      stream_name: "Identity",
      stream_id: identity
    )
    build_event = lambda do
      PgEventstore::Event.new(
        id: event_id,
        type: "NaturalKeyRegisteredProbe",
        data: { "identity" => identity, "value" => value },
        metadata: { "schema_version" => 1 },
        markers: [ marker ]
      )
    end
    identity_from = ->(event) { event.data["identity"] if event.data["value"] == value }

    registry.call(
      selector: selector(marker),
      proposed_stream: stream,
      build_event:,
      identity_from:
    )
  end

  def registrations(marker)
    event_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "RegistryProbe",
        stream_name: "Identity",
        event_types: [ "NaturalKeyRegisteredProbe" ],
        markers: [ marker ],
        maximum_count: 2,
        direction: :asc
      )
    )
  end

  it "converges concurrent identical registrations on one persisted UUIDv7" do
    marker = marker_for("same")
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ready << true
        start.pop
        registration("same", marker:)
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = threads.map(&:value)

    expect(results).to all(be_success)
    expect(results.map { _1.value!.identity }.uniq.one?).to be(true)
    expect(results.map { _1.value!.outcome }).to contain_exactly("created", "existing")
    expect(registrations(marker).map(&:id)).to contain_exactly(results.first.value!.event.id)
  end

  it "allows concurrent distinct natural selectors to allocate different UUIDv7 streams" do
    results = %w[first second].map do |value|
      Thread.new { registration(value) }
    end.map(&:value)

    expect(results).to all(be_success)
    expect(results.map { _1.value!.identity }.uniq.length).to eq(2)
    expect(results.map { _1.value!.outcome }).to contain_exactly("created", "created")
  end

  it "fails closed when a selector already identifies multiple registration facts" do
    marker = marker_for("duplicate")
    two_events = 2.times.map do
      identity = id_generator.uuid_v7
      stream = Coordinator::Write::StreamReference.new(
        context: "RegistryProbe",
        stream_name: "Identity",
        stream_id: identity
      )
      event = PgEventstore::Event.new(
        id: id_generator.uuid_v7,
        type: "NaturalKeyRegisteredProbe",
        data: { "identity" => identity, "value" => "duplicate" },
        metadata: { "schema_version" => 1 },
        markers: [ marker ]
      )
      event_store.append(stream, [ event ]).sole
    end

    failure = registration("duplicate", marker:).failure

    expect(failure).to have_attributes(
      code: :duplicate_registration,
      event_ids: match_array(two_events.map(&:id))
    )
  end

  it "fails closed when persisted data does not reconstruct the selected tuple" do
    marker = marker_for("requested")
    registration("different", marker:)

    failure = registration("requested", marker:).failure

    expect(failure.code).to eq(:existing_registration_invalid)
    expect(registrations(marker).length).to eq(1)
  end
end
