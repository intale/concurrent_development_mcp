# frozen_string_literal: true

RSpec.describe Coordinator::Write::EventStore, :event_store do
  subject(:event_store) { described_class.new(client: PgEventstore.client) }

  let(:stream) { Coordinator::Write::StreamFactory.new.change_set("CS-real-store") }
  let(:probe_read) do
    Coordinator::Write::EventReadCriteria.new(
      event_types: [ "RealStoreProbe" ],
      maximum_count: 1,
      direction: :asc
    )
  end
  let(:event) { build_event(type: "RealStoreProbe", data: { "probe" => true }) }

  def build_event(type:, data: {}, markers: [])
    PgEventstore::Event.new(
      id: Coordinator::Shared::IdGenerator.new.uuid_v7,
      type:,
      data:,
      metadata: { "schema_version" => 1 },
      markers:
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
      .to raise_error(Coordinator::Write::EventHistoryLimitExceeded, /exceeded 1 relevant events/)
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
    criteria = Coordinator::Write::GroupedEventReadCriteria.new(
      event_types: [ "RealStoreProbe", "OtherProbe" ],
      direction: :desc
    )

    grouped_events = event_store.read_grouped(stream, criteria)
    grouped = grouped_events.to_h { [ _1.type, _1 ] }

    expect(grouped_events.map(&:stream_revision)).to eq([ 2, 1 ])
    expect(grouped.fetch("RealStoreProbe").id).to eq(newest_probe.id)
    expect(grouped.fetch("OtherProbe").data).to eq("version" => 1)
  end

  it "reloads one exact specific-stream revision without scanning the stream" do
    first = build_event(type: "FirstProbe")
    target = build_event(type: "TargetProbe")
    event_store.append(stream, [ first, target, build_event(type: "LaterProbe") ])

    expect(event_store.read_at(stream, 1)).to have_attributes(id: target.id, stream_revision: 1)
    expect(event_store.read_at(stream, 9)).to be_nil
  end

  it "reloads one exact global position without scanning the global stream" do
    target = event_store.append(stream, [ build_event(type: "GlobalTargetProbe") ]).sole

    expect(event_store.read_global_at(target.global_position)).to have_attributes(
      id: target.id,
      global_position: target.global_position
    )
    expect(event_store.read_global_at(target.global_position + 1_000_000)).to be_nil
  end

  it "reads one latest matching event without treating older matches as overflow" do
    newest = build_event(type: "TargetProbe")
    event_store.append(
      stream,
      [ build_event(type: "TargetProbe"), build_event(type: "IgnoredProbe"), newest ]
    )

    criteria = Coordinator::Write::LatestEventReadCriteria.new(event_types: [ "TargetProbe" ])
    expect(event_store.read_latest(stream, criteria)).to have_attributes(id: newest.id, stream_revision: 2)
  end

  it "uses one compound marker as a bounded conjunctive event selector" do
    target = build_event(
      type: "RealStoreProbe",
      markers: [
        "locale:en",
        "resource:description",
        "compound:description:v2|9:locale=en|20:resource=description"
      ]
    )
    event_store.append(
      stream,
      [
        build_event(type: "RealStoreProbe", markers: [ "locale:en" ]),
        build_event(type: "RealStoreProbe", markers: [ "resource:description" ]),
        target
      ]
    )
    criteria = Coordinator::Write::MarkedEventReadCriteria.new(
      event_type: "RealStoreProbe",
      marker: "compound:description:v2|9:locale=en|20:resource=description",
      maximum_count: 1,
      direction: :desc
    )

    expect(event_store.read_marked(stream, criteria).map(&:id)).to eq([ target.id ])
  end

  it "reads only the latest matching fact from a marker-partitioned stream" do
    marker = "resource-boundary:v2|r=36:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}|" \
      "role=13:resource-path|p=6:app.rb"
    newest = build_event(type: "ResourceBoundaryEpochRolled", markers: [ marker ])
    event_store.append(
      stream,
      [
        build_event(type: "ResourceBoundaryEpochRolled", markers: [ marker ]),
        build_event(type: "ResourceBoundaryEpochRolled", markers: [ "another-boundary" ]),
        newest
      ]
    )
    criteria = Coordinator::Write::LatestMarkedEventReadCriteria.new(
      event_type: "ResourceBoundaryEpochRolled",
      marker:
    )

    expect(event_store.read_latest_marked(stream, criteria).map(&:id)).to eq([ newest.id ])
  end

  it "reads one globally marked fact only within the declared context, stream name, and types" do
    target = build_event(type: "UserUtteranceRecorded", markers: [ "message:M-real-store" ])
    event_store.append(
      Coordinator::Write::StreamFactory.new.conversation("C-real-store"),
      [ target ]
    )
    event_store.append(
      stream,
      [ build_event(type: "UserUtteranceRecorded", markers: [ "message:M-real-store" ]) ]
    )

    criteria = Coordinator::Write::EventQueries.guidance_message("message:M-real-store")

    expect(event_store.read_global_marked(criteria).map(&:id)).to eq([ target.id ])
  end

  it "limits the latest globally marked match to the requested inclusive position window" do
    marker = "work-intention:#{SecureRandom.uuid_v7}"
    reference = Coordinator::Write::StreamFactory.new.resource_work_intention(SecureRandom.uuid_v7)
    first, previous, current, later = event_store.append(
      reference, Array.new(4) { build_event(type: "ResourceWorkIntentionRenewed", markers: [ marker ]) }
    )
    criteria = Coordinator::Write::GlobalMarkedEventReadCriteria.new(
      stream_context: reference.context, stream_name: reference.stream_name,
      event_types: [ "ResourceWorkIntentionRenewed" ], markers: [ marker ],
      maximum_count: 1, direction: :desc,
      from_position: current.global_position, to_position: previous.global_position
    )

    expect(event_store.read_latest_global_marked(criteria)).to have_attributes(id: current.id)
    expect([ first.id, later.id ]).not_to include(event_store.read_latest_global_marked(criteria).id)
  end

  it "reads one bounded global page using an intentional OR union of markers" do
    choice_streams = Coordinator::Write::StreamFactory.new
    first = event_store.append(
      choice_streams.agent_choice("CHO-page-1"),
      [ build_event(type: "AgentChoiceAccepted", markers: [ "decision-partition:repo:billing:testing" ]) ]
    ).sole
    event_store.append(
      choice_streams.agent_choice("CHO-page-ignored"),
      [ build_event(type: "AgentChoiceAccepted", markers: [ "decision-partition:repo:catalog:testing" ]) ]
    )
    second = event_store.append(
      choice_streams.agent_choice("CHO-page-2"),
      [ build_event(type: "AgentChoiceAccepted", markers: [ "decision-partition:attempt:A-2:testing" ]) ]
    ).sole
    event_store.append(
      choice_streams.agent_choice("CHO-page-after-bound"),
      [ build_event(type: "AgentChoiceAccepted", markers: [ "decision-partition:repo:billing:testing" ]) ]
    )
    criteria = Coordinator::Write::GlobalMarkedEventPageCriteria.new(
      stream_context: "AgentGovernance",
      stream_name: "AgentChoice",
      event_type: "AgentChoiceAccepted",
      markers: [
        "decision-partition:repo:billing:testing",
        "decision-partition:attempt:A-2:testing"
      ],
      from_position: first.global_position,
      to_position: second.global_position,
      page_size: 1,
      direction: :asc
    )

    page = event_store.read_global_marked_page(criteria)

    expect(page.map(&:id)).to eq([ first.id, second.id ])
    expect(page.map(&:global_position)).to eq(page.map(&:global_position).sort)
    expect(page.length).to eq(criteria.page_size + 1)
  end

  it "reads a specific-stream revision page using an intentional OR union of compound markers" do
    registry = Coordinator::Write::StreamFactory.new.candidate_impact_registry("CS-marker-page")
    events = Array.new(55) do |index|
      build_event(
        type: "CandidateImpactSurfaceRegistered",
        markers: [ index.even? ? "compound:candidate-impact-index:v2|5:key=a" :
          "compound:candidate-impact-index:v2|5:key=b" ]
      )
    end
    event_store.append(registry, events)
    criteria = Coordinator::Write::StreamMarkedEventPageCriteria.new(
      event_type: "CandidateImpactSurfaceRegistered",
      markers: [
        "compound:candidate-impact-index:v2|5:key=a",
        "compound:candidate-impact-index:v2|5:key=b"
      ],
      from_revision: 2,
      to_revision: 53,
      page_size: 50,
      direction: :asc
    )

    page = event_store.read_stream_marked_page(registry, criteria)

    expect(page.length).to eq(51)
    expect(page.map(&:stream_revision)).to eq((2..52).to_a)
    expect(page.map(&:type).uniq).to eq([ "CandidateImpactSurfaceRegistered" ])
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
