# frozen_string_literal: true

RSpec.describe Coordinator::Read::Web::Queries::CoordinationDashboard, :read_model do
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000021" }

  before do
    create(
      :coordinator_read_repository,
      repository_id:,
      repository_key: "dashboard",
      scope: "project:dashboard",
      display_name: "Dashboard"
    )
    seed_dashboard_projection
  end

  it "maps exact WorkItem and unbounded active Attempt facts to presentation states" do
    dashboard = query

    expect(dashboard.project).to have_attributes(
      repository_id:,
      display_name: "Dashboard"
    )
    expect(dashboard.work_items.items.map(&:presentation_status)).to eq(
      %w[pending ready assigned running completed]
    )
    running = dashboard.work_items.items.fetch(3)
    expect(running).to have_attributes(
      work_item_id: "W-4-running",
      domain_status: "acquired",
      active_attempt_id: "A-running",
      active_agent_id: "luna-two",
      attempt_status: "started",
      attempt_started_at: "2026-08-31T12:04:00.000000Z"
    )
    expect(dashboard.change_sets.items.sole).to have_attributes(
      work_item_count: 5,
      running_work_item_count: 1,
      open_work_item_count: 3
    )
  end

  it "applies bounded filtering, sorting, and offsets in the semantic read query" do
    first = query(first: 1, presentation_statuses: [ "running", "ready" ], work_item_sort: "status_asc")
    second = query(
      first: 1,
      work_item_offset: first.work_items.next_offset,
      presentation_statuses: [ "running", "ready" ],
      work_item_sort: "status_asc"
    )
    blockers = query(blocking: true)

    expect(first.work_items.items.map(&:presentation_status)).to eq([ "ready" ])
    expect(first.work_items).to have_attributes(next_offset: 1, has_more: true)
    expect(second.work_items.items.map(&:presentation_status)).to eq([ "running" ])
    expect(blockers.dependencies.items.map(&:dependency_id)).to eq([ "D-blocking" ])
  end

  it "returns nil for a repository absent from the latest read projection" do
    result = described_class.new.call(repository_id: "018f0f4d-4e45-7abc-8def-000000000099")

    expect(result).to be_nil
  end

  it "validates the public read contract with dry-validation" do
    expect { described_class.new.call(repository_id: "not-a-repository", first: 101) }
      .to raise_error(Coordinator::Read::Web::CoordinationDashboardQueryError) do |error|
        expect(error.details.keys).to contain_exactly(:repository_id, :first)
      end
  end

  def query(**input)
    described_class.new.call({ repository_id:, first: 20 }.merge(input))
  end

  def seed_dashboard_projection
    context = build(
      :coordinator_read_coord_context,
      change_set_id: "CS-dashboard",
      repository_id:,
      work_item_id: "W-default",
      attempt_id: "A-default"
    )
    default = context.document.fetch("work_items").sole
    context.document["work_items"] = [
      work_item(default, id: "W-1-pending", status: "planned"),
      work_item(default, id: "W-2-ready", status: "ready"),
      work_item(default, id: "W-3-assigned", status: "acquired", attempt_id: "A-assigned"),
      work_item(default, id: "W-4-running", status: "acquired", attempt_id: "A-running"),
      work_item(default, id: "W-5-completed", status: "completed")
    ]
    context.document["work_item_ids"] = context.document.fetch("work_items").map { _1.fetch("work_item_id") }
    context.document["attempts"] = []
    context.document["dependencies"] = [
      dependency("D-blocking", "W-1-pending", "W-2-ready", nil),
      dependency("D-satisfied", "W-2-ready", "W-5-completed", "2026-08-31T12:05:00.000000Z")
    ]
    context.save!

    create(
      :coordinator_read_attempt_history,
      attempt_id: "A-assigned",
      change_set_id: "CS-dashboard",
      work_item_id: "W-3-assigned",
      agent_id: "luna-one",
      status: "authorized"
    )
    create(
      :coordinator_read_attempt_history,
      attempt_id: "A-running",
      change_set_id: "CS-dashboard",
      work_item_id: "W-4-running",
      agent_id: "luna-two",
      status: "started",
      started_at_domain: Time.utc(2026, 8, 31, 12, 4)
    )
  end

  def work_item(default, id:, status:, attempt_id: nil)
    default.merge(
      "work_item_id" => id,
      "goal" => "Coordinate #{id}",
      "status" => status,
      "active_attempt_id" => attempt_id,
      "active_agent_id" => attempt_id && "embedded-agent",
      "acquired_at" => attempt_id && "2026-08-31T12:03:00.000000Z",
      "completed_at" => status == "completed" ? "2026-08-31T12:06:00.000000Z" : nil
    )
  end

  def dependency(id, producer, consumer, satisfied_at)
    {
      "dependency_id" => id,
      "producer_work_item_id" => producer,
      "consumer_work_item_id" => consumer,
      "dependency_kind" => "requires_completion",
      "required_output" => nil,
      "source_event" => nil,
      "declared_at" => "2026-08-31T12:00:00.000000Z",
      "satisfied_at" => satisfied_at
    }
  end
end
