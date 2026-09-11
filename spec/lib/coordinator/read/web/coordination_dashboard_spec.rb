# frozen_string_literal: true

RSpec.describe Coordinator::Read::Web::Queries::CoordinationDashboard, :read_model do
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000021" }
  let(:scope) { "project:dashboard" }
  let(:project_ref) { Coordinator::Read::Web::ProjectReference.new.encode(scope:) }

  before do
    create(
      :coordinator_read_repository,
      repository_id:,
      repository_key: "dashboard",
      scope:,
      display_name: "Dashboard"
    )
    seed_dashboard_projection
  end

  it "maps exact WorkItem and unbounded active Attempt facts to presentation states" do
    work_items = page("work_items", work_item_sort: "status_asc")
    change_sets = page("change_sets")

    expect(work_items.items.map(&:presentation_status)).to eq(
      %w[pending ready assigned running completed]
    )
    running = work_items.items.fetch(3)
    expect(running).to have_attributes(
      work_item_id: "W-4-running",
      domain_status: "acquired",
      active_attempt_id: "A-running",
      active_agent_id: "luna-two",
      attempt_status: "started",
      attempt_started_at: "2026-08-31T12:04:00.000000Z"
    )
    expect(change_sets.items.sole).to have_attributes(
      work_item_count: 5,
      running_work_item_count: 1,
      open_work_item_count: 3
    )
  end

  it "applies bounded filtering and tuple-key continuation" do
    first = page(
      "work_items",
      first: 3,
      work_item_sort: "status_asc"
    )
    second = page(
      "work_items",
      first: 2,
      after_id: first.next_cursor.id,
      after_sort_value: first.next_cursor.sort_value,
      work_item_sort: "status_asc"
    )
    blockers = page("dependencies", blocking: true)

    expect(first.items.map(&:presentation_status)).to eq(%w[pending ready assigned])
    expect(first).to have_attributes(has_more: true)
    expect(first.next_cursor).to have_attributes(id: "W-3-assigned", sort_value: "2")
    expect(second.items.map(&:presentation_status)).to eq(%w[running completed])
    expect(blockers.items.map(&:dependency_id)).to eq([ "D-blocking" ])
  end

  it "returns project-bound details through the semantic query" do
    detail = described_class.new.detail(project_ref:, kind: "work_items", id: "W-4-running")

    expect(detail.work_item).to have_attributes(
      work_item_id: "W-4-running",
      presentation_status: "running"
    )
    expect(detail.attempt).to have_attributes(
      attempt_id: "A-running",
      agent_id: "luna-two",
      status: "started"
    )
  end

  it "returns nil for a Project absent from the latest read projection" do
    missing_ref = Coordinator::Read::Web::ProjectReference.new.encode(scope: "project:missing")

    expect(described_class.new.page(project_ref: missing_ref, kind: "change_sets")).to be_nil
  end

  it "validates the public read contract with dry-validation" do
    expect { described_class.new.page(project_ref:, kind: "unsupported", first: 101) }
      .to raise_error(Coordinator::Read::Web::CoordinationDashboardQueryError) do |error|
        expect(error.details.keys).to contain_exactly(:kind, :first)
      end
    expect do
      page(
        "work_items",
        after_id: "W-3-assigned",
        after_sort_value: "assigned",
        work_item_sort: "status_asc"
      )
    end.to raise_error(Coordinator::Read::Web::CoordinationDashboardQueryError) do |error|
      expect(error.details).to include(after_sort_value: include("is invalid for this sort"))
    end
  end

  def page(kind, **input)
    described_class.new.page({ project_ref:, kind:, first: 20 }.merge(input))
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
