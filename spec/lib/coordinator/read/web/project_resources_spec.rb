# frozen_string_literal: true

RSpec.describe Coordinator::Read::Web::Queries::ProjectResources, :read_model do
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000041" }
  let(:as_of) { "2026-08-30T12:05:00.000000Z" }
  let(:resource_ids) do
    %w[
      018f0f4d-4e45-7abc-8def-000000000042
      018f0f4d-4e45-7abc-8def-000000000043
      018f0f4d-4e45-7abc-8def-000000000044
    ]
  end
  let(:lease_ids) do
    %w[
      018f0f4d-4e45-7abc-8def-000000000052
      018f0f4d-4e45-7abc-8def-000000000053
      018f0f4d-4e45-7abc-8def-000000000054
    ]
  end

  before do
    create(
      :coordinator_read_repository,
      repository_id:,
      repository_key: "resource-browser",
      scope: "project:resource-browser",
      display_name: "Resource browser"
    )
    create(
      :coordinator_read_resource,
      resource_id: resource_ids.fetch(0),
      repository_id:,
      normalized_path: "app/models/active_one.rb"
    )
    create(
      :coordinator_read_resource,
      resource_id: resource_ids.fetch(1),
      repository_id:,
      normalized_path: "app/models/active_two.rb"
    )
    create(
      :coordinator_read_resource,
      :inactive,
      resource_id: resource_ids.fetch(2),
      repository_id:,
      normalized_path: "app/models/released.rb"
    )

    create_lease_attempt("A-active-one", resource_ids.fetch(0), lease_ids.fetch(0), "luna-one")
    create_lease_attempt("A-active-two", resource_ids.fetch(1), lease_ids.fetch(1), "luna-two")
    create_lease_attempt(
      "A-released",
      resource_ids.fetch(2),
      lease_ids.fetch(2),
      "luna-released",
      released: true
    )
    create(
      :coordinator_read_attempt_history,
      attempt_id: "A-running-without-lease",
      change_set_id: "CS-resource-browser",
      work_item_id: "W-running-without-lease",
      agent_id: "luna-no-lease",
      status: "started",
      base_snapshots: snapshots
    )
  end

  it "serves resources and factual active leases without inferring ownership from running status" do
    browser = query(first: 20)

    expect(browser.project).to have_attributes(
      repository_id:,
      scope: "project:resource-browser",
      display_name: "Resource browser"
    )
    expect(browser.resources.items.map(&:resource_id)).to eq(resource_ids)
    expect(browser.active_leases.items.map(&:lease_id)).to eq(lease_ids.first(2))
    expect(browser.active_leases.items.map(&:agent_id)).to eq(%w[luna-one luna-two])
    expect(browser.active_leases.items.map(&:attempt_id)).not_to include("A-running-without-lease")
    expect(browser.lease_as_of).to eq(as_of)

    released = Coordinator::Read::ResourceLeaseBrowserRow.find(lease_ids.fetch(2))
    expect(released).to have_attributes(
      resource_path: "app/models/released.rb",
      released_at_domain: Time.utc(2026, 8, 30, 12, 4)
    )
    expect(released.release_event.fetch("type")).to eq("WriteSetReleased")
  end

  it "uses stable keyset cursors and one captured as-of value across active-lease pages" do
    first = query(first: 1)
    second = query(
      first: 1,
      resource_after_id: first.resources.next_resource_id,
      lease_after_id: first.active_leases.next_lease_id,
      lease_as_of: first.lease_as_of
    )

    expect(first.resources).to have_attributes(has_more: true, next_resource_id: resource_ids.fetch(0))
    expect(first.active_leases).to have_attributes(has_more: true, next_lease_id: lease_ids.fetch(0))
    expect(second.resources.items.map(&:resource_id)).to eq([ resource_ids.fetch(1) ])
    expect(second.active_leases.items.map(&:lease_id)).to eq([ lease_ids.fetch(1) ])
    expect(second.lease_as_of).to eq(first.lease_as_of)
  end

  it "filters resource inventory independently from active lease ownership" do
    browser = query(resource_lifecycle_status: "inactive")

    expect(browser.resources.items.map(&:resource_id)).to eq([ resource_ids.fetch(2) ])
    expect(browser.active_leases.items.map(&:resource_id)).to eq(resource_ids.first(2))
  end

  it "rejects malformed identifiers and timestamps through its dry contract" do
    expect do
      described_class.new.call(repository_id: "not-a-repository", lease_as_of: "yesterday")
    end.to raise_error(Coordinator::Read::Web::ProjectResourcesQueryError) do |error|
      expect(error.details.keys).to contain_exactly(:repository_id, :lease_as_of)
    end
  end

  def query(**input)
    described_class.new.call({ repository_id:, first: 20, lease_as_of: as_of }.merge(input))
  end

  def create_lease_attempt(attempt_id, resource_id, lease_id, agent_id, released: false)
    create(
      :coordinator_read_attempt_history,
      released ? :released_write_set : :with_write_set,
      attempt_id:,
      change_set_id: "CS-resource-browser",
      work_item_id: "W-#{attempt_id}",
      agent_id:,
      status: "started",
      base_snapshots: snapshots,
      write_set_resource_id: resource_id,
      write_set_resource_path: Coordinator::Read::Resource.find(resource_id).normalized_path,
      write_set_lease_id: lease_id,
      write_set_lease_set_id: lease_set_id(lease_id),
      write_set_expires_at_domain: Time.utc(2026, 8, 30, 12, 20),
      write_set_released_at_domain: released ? Time.utc(2026, 8, 30, 12, 4) : nil
    )
  end

  def snapshots
    [ { "repository_id" => repository_id, "object_format" => "sha1", "commit_oid" => "a" * 40 } ]
  end

  def lease_set_id(lease_id)
    lease_id.sub(/005([234])\z/) { format("006%d", Regexp.last_match(1).to_i) }
  end
end
