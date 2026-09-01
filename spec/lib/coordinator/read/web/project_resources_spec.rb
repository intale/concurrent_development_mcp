# frozen_string_literal: true

RSpec.describe Coordinator::Read::Web::Queries::ProjectResources, :read_model do
  let(:scope) { "project:resource-browser" }
  let(:project_ref) { Coordinator::Read::Web::ProjectReference.new.encode(scope:) }
  let(:as_of) { "2026-08-30T12:05:00.000000Z" }
  let(:repository_ids) do
    %w[
      018f0f4d-4e45-7abc-8def-000000000041
      018f0f4d-4e45-7abc-8def-000000000042
    ]
  end
  let(:resource_ids) do
    %w[
      018f0f4d-4e45-7abc-8def-000000000051
      018f0f4d-4e45-7abc-8def-000000000052
      018f0f4d-4e45-7abc-8def-000000000053
    ]
  end
  let(:lease_ids) do
    %w[
      018f0f4d-4e45-7abc-8def-000000000061
      018f0f4d-4e45-7abc-8def-000000000062
      018f0f4d-4e45-7abc-8def-000000000063
    ]
  end

  before do
    repository_ids.each_with_index do |repository_id, index|
      create(
        :coordinator_read_repository,
        repository_id:,
        repository_key: "resource-browser-#{index}",
        scope:,
        display_name: "Resource browser #{index + 1}"
      )
    end
    create(
      :coordinator_read_repository,
      repository_id: "018f0f4d-4e45-7abc-8def-000000000049",
      repository_key: "outside-resource-browser",
      scope: "project:outside"
    )
    create_resource(resource_ids.fetch(0), repository_ids.fetch(0), "app/models/active_one.rb")
    create_resource(resource_ids.fetch(1), repository_ids.fetch(1), "app/services/active_two.rb")
    create_resource(
      resource_ids.fetch(2),
      repository_ids.fetch(0),
      "app/models/inactive.rb",
      trait: :inactive
    )
    @outside_resource = create_resource(
      "018f0f4d-4e45-7abc-8def-000000000059",
      "018f0f4d-4e45-7abc-8def-000000000049",
      "private/outside.rb"
    )

    create_lease_attempt("A-active", resource_ids.fetch(0), lease_ids.fetch(0), "luna-owner")
    create_lease_attempt(
      "A-expired",
      resource_ids.fetch(1),
      lease_ids.fetch(1),
      "luna-expired",
      expires_at: Time.utc(2026, 8, 30, 12, 4)
    )
    create_lease_attempt(
      "A-released",
      resource_ids.fetch(2),
      lease_ids.fetch(2),
      "luna-released",
      released: true
    )
  end

  it "pages and filters Resource inventory across every exact-scope Repository" do
    first = described_class.new.resources(
      project_ref:,
      first: 1,
      as_of:,
      path: "app/"
    )
    second = described_class.new.resources(
      project_ref:,
      first: 1,
      as_of:,
      path: "app/",
      after_id: first.next_resource_id
    )
    inactive = described_class.new.resources(
      project_ref:,
      first: 20,
      as_of:,
      resource_lifecycle_status: "inactive"
    )

    expect(first).to have_attributes(has_more: true, next_resource_id: resource_ids.fetch(0))
    expect(first.items.map(&:resource_id)).to eq([ resource_ids.fetch(0) ])
    expect(second.items.map(&:resource_id)).to eq([ resource_ids.fetch(1) ])
    expect(inactive.items.map(&:resource_id)).to eq([ resource_ids.fetch(2) ])
  end

  it "uses ResourceGet for project-bound detail evidence and hides another Project" do
    resource = described_class.new.resource(project_ref:, id: resource_ids.fetch(0), as_of:)
    outside = described_class.new.resource(project_ref:, id: @outside_resource.resource_id, as_of:)

    expect(resource).to have_attributes(
      resource_id: resource_ids.fetch(0),
      repository_id: repository_ids.fetch(0),
      registered_actor_id: "factory-agent",
      registered_at: "2026-08-30T12:00:00.000000Z",
      last_transition_at: "2026-08-30T12:01:00.000000Z"
    )
    expect(resource.registered_event_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(outside).to be_nil
  end

  it "lists only factual active leases with server-side holder and coordination filters" do
    active = described_class.new.active_leases(
      project_ref:,
      first: 20,
      as_of:,
      agent_id: "luna-owner",
      work_item_id: "W-A-active"
    )
    none = described_class.new.active_leases(
      project_ref:,
      first: 20,
      as_of:,
      attempt_id: "A-running-without-lease"
    )

    expect(active.items.sole).to have_attributes(
      lease_id: lease_ids.fetch(0),
      status: "active",
      agent_id: "luna-owner",
      attempt_id: "A-active"
    )
    expect(active.as_of).to eq(as_of)
    expect(none.items).to be_empty
  end

  it "keeps expired and released lease history addressable without presenting it as active" do
    expired = described_class.new.lease(project_ref:, id: lease_ids.fetch(1), as_of:)
    released = described_class.new.lease(project_ref:, id: lease_ids.fetch(2), as_of:)

    expect(expired).to have_attributes(status: "expired", agent_id: "luna-expired", released_at: nil)
    expect(released).to have_attributes(
      status: "released",
      agent_id: "luna-released",
      released_at: "2026-08-30T12:04:00.000000Z"
    )
    expect(released.release_event_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
  end

  it "rejects malformed identifiers and canonical timestamps through dry contracts" do
    expect do
      described_class.new.lease(project_ref:, id: "not-a-lease", as_of: "yesterday")
    end.to raise_error(Coordinator::Read::Web::ProjectResourcesQueryError) do |error|
      expect(error.details.keys).to contain_exactly(:id, :as_of)
    end
  end

  def create_resource(resource_id, repository_id, path, trait: nil)
    arguments = [ :coordinator_read_resource ]
    arguments << trait if trait
    create(*arguments, resource_id:, repository_id:, normalized_path: path)
  end

  def create_lease_attempt(attempt_id, resource_id, lease_id, agent_id, expires_at: nil, released: false)
    repository_id = Coordinator::Read::Resource.find(resource_id).repository_id
    create(
      :coordinator_read_attempt_history,
      released ? :released_write_set : :with_write_set,
      attempt_id:,
      change_set_id: "CS-resource-browser",
      work_item_id: "W-#{attempt_id}",
      agent_id:,
      status: "started",
      base_snapshots: snapshots(repository_id),
      write_set_repository_id: repository_id,
      write_set_resource_id: resource_id,
      write_set_resource_path: Coordinator::Read::Resource.find(resource_id).normalized_path,
      write_set_lease_id: lease_id,
      write_set_lease_set_id: SecureRandom.uuid_v7,
      write_set_expires_at_domain: expires_at || Time.utc(2026, 8, 30, 12, 20),
      write_set_released_at_domain: released ? Time.utc(2026, 8, 30, 12, 4) : nil
    )
  end

  def snapshots(repository_id)
    [ { "repository_id" => repository_id, "object_format" => "sha1", "commit_oid" => "a" * 40 } ]
  end
end
