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
  let(:intention_ids) do
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

    create_work_intention_attempt("A-active", resource_ids.fetch(0), intention_ids.fetch(0), "luna-owner")
    create_work_intention_attempt(
      "A-expired",
      resource_ids.fetch(1),
      intention_ids.fetch(1),
      "luna-expired",
      expires_at: Time.utc(2026, 8, 30, 12, 4)
    )
    create_work_intention_attempt(
      "A-withdrawn",
      resource_ids.fetch(2),
      intention_ids.fetch(2),
      "luna-withdrawn",
      withdrawn: true,
      mode: "exclusive",
      context: "Wait for the translation rewrite to finish"
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
      after_id: first.next_resource_id,
      after_updated_at: first.next_updated_at
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

  it "lists active advisory work intentions with server-side mode and coordination filters" do
    active = described_class.new.active_work_intentions(
      project_ref:,
      first: 20,
      as_of:,
      agent_id: "luna-owner",
      work_item_id: "W-A-active",
      mode: "shared"
    )
    none = described_class.new.active_work_intentions(
      project_ref:,
      first: 20,
      as_of:,
      attempt_id: "A-running-without-intention"
    )

    expect(active.items.sole).to have_attributes(
      intention_id: intention_ids.fetch(0),
      status: "active",
      mode: "shared",
      purpose: "Implement A-active",
      agent_id: "luna-owner",
      attempt_id: "A-active"
    )
    expect(active.as_of).to eq(as_of)
    expect(none.items).to be_empty
  end

  it "keeps expired and withdrawn intention history addressable without presenting it as active" do
    expired = described_class.new.work_intention(project_ref:, id: intention_ids.fetch(1), as_of:)
    withdrawn = described_class.new.work_intention(project_ref:, id: intention_ids.fetch(2), as_of:)

    expect(expired).to have_attributes(status: "expired", agent_id: "luna-expired", withdrawn_at: nil)
    expect(withdrawn).to have_attributes(
      status: "withdrawn",
      agent_id: "luna-withdrawn",
      mode: "exclusive",
      context: "Wait for the translation rewrite to finish",
      withdrawn_at: "2026-08-30T12:04:00.000000Z"
    )
    expect(withdrawn.withdrawal_event_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
  end

  it "rejects malformed identifiers and canonical timestamps through dry contracts" do
    expect do
      described_class.new.work_intention(project_ref:, id: "not-an-intention", as_of: "yesterday")
    end.to raise_error(Coordinator::Read::Web::ProjectResourcesQueryError) do |error|
      expect(error.details.keys).to contain_exactly(:id, :as_of)
    end
  end

  def create_resource(resource_id, repository_id, path, trait: nil)
    arguments = [ :coordinator_read_resource ]
    arguments << trait if trait
    index = resource_ids.index(resource_id) || resource_ids.length
    projected_at = Time.utc(2026, 8, 30, 12, 2) - index.seconds
    create(
      *arguments,
      resource_id:,
      repository_id:,
      normalized_path: path,
      created_at: projected_at,
      updated_at: projected_at
    )
  end

  def create_work_intention_attempt(
    attempt_id,
    resource_id,
    intention_id,
    agent_id,
    expires_at: nil,
    withdrawn: false,
    mode: "shared",
    context: nil
  )
    repository_id = Coordinator::Read::Resource.find(resource_id).repository_id
    create(
      :coordinator_read_attempt_history,
      withdrawn ? :withdrawn_work_intention_set : :with_work_intention_set,
      attempt_id:,
      change_set_id: "CS-resource-browser",
      work_item_id: "W-#{attempt_id}",
      agent_id:,
      status: "started",
      base_snapshots: snapshots(repository_id),
      work_intention_set_repository_id: repository_id,
      work_intention_resource_id: resource_id,
      work_intention_resource_path: Coordinator::Read::Resource.find(resource_id).normalized_path,
      work_intention_id: intention_id,
      work_intention_mode: mode,
      work_intention_purpose: "Implement #{attempt_id}",
      work_intention_context: context,
      work_intention_set_id: SecureRandom.uuid_v7,
      work_intention_set_expires_at_domain: expires_at || Time.utc(2026, 8, 30, 12, 20),
      work_intention_set_withdrawn_at_domain: withdrawn ? Time.utc(2026, 8, 30, 12, 4) : nil
    )
  end

  def snapshots(repository_id)
    [ { "repository_id" => repository_id, "object_format" => "sha1", "commit_oid" => "a" * 40 } ]
  end
end
