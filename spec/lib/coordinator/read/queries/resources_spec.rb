# frozen_string_literal: true

RSpec.describe "Resource discovery queries", :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:repository_id) { RepositoryScenario::DEFAULT_REPOSITORY_ID }
  let(:projector) { Coordinator::Read::Projectors::ResourcesV1.new }

  before { RepositoryScenario.register(event_store:) }

  it "gets stale available lifecycle state and pages a Repository in UUID order" do
    first = resolve("cmd-resource-query-1", "app/models/query_one.rb", "file")
    second = resolve("cmd-resource-query-2", "app/models/query_two.rb", "file")
    third = resolve("cmd-resource-query-3", "app/services", "directory")
    [ first, second, third ].each { project_all(_1) }
    remove(first)

    available = Coordinator::Read::Queries::ResourceGet.new.call(resource_id: first).value!
    expect(available).to have_attributes(status: "ok")
    expect(available.data.resource).to have_attributes(lifecycle_status: "current")

    project_all(first)
    inactive = Coordinator::Read::Queries::ResourceGet.new.call(resource_id: first).value!
    expect(inactive.data.resource).to have_attributes(
      lifecycle_status: "inactive",
      unbinding_reason: "removed"
    )

    query = Coordinator::Read::Queries::ResourceList.new
    first_page = query.call(repository_id:, limit: 2).value!.data.page
    second_page = query.call(
      repository_id:,
      after_resource_id: first_page.next_resource_id,
      limit: 2
    ).value!.data.page
    expect(first_page).to have_attributes(has_more: true)
    expect(second_page).to have_attributes(has_more: false, next_resource_id: nil)
    expect((first_page.items + second_page.items).map(&:resource_id)).to eq(
      Coordinator::Read::Resource.order(:resource_id).pluck(:resource_id)
    )

    filtered = query.call(repository_id:, kind: "file", lifecycle_status: "current").value!.data.page
    expect(filtered.items.map(&:resource_id)).to eq([ second ])
  end

  it "returns typed absent and invalid results without consulting the write store" do
    absent = Coordinator::Read::Queries::ResourceGet.new.call(
      resource_id: "01a03deb-ffff-7fff-8fff-ffffffffffff"
    ).value!
    invalid_get = Coordinator::Read::Queries::ResourceGet.new.call(resource_id: "resource-1").value!
    invalid_list = Coordinator::Read::Queries::ResourceList.new.call(
      repository_id:,
      lifecycle_status: "pending",
      limit: 101
    ).value!

    expect(absent).to have_attributes(status: "not_found")
    expect(absent.data).to have_attributes(code: "resource_not_observed")
    expect(invalid_get).to have_attributes(status: "invalid")
    expect(invalid_list).to have_attributes(status: "invalid")
  end

  def resolve(command_id, path, kind)
    result = Coordinator::Write::Operations::ExecuteResolveResource.new(event_store:).call(
      command_id:,
      actor: { kind: "agent", id: "resource-query-agent" },
      repository_id:,
      kind:,
      path:
    )
    expect(result).to be_success
    result.value!.data.resource_id
  end

  def remove(resource_id)
    result = Coordinator::Write::Operations::ExecuteRemoveResource.new(event_store:).call(
      command_id: "cmd-resource-query-remove-#{resource_id}",
      actor: { kind: "agent", id: "resource-query-agent" },
      resource_id:,
      reason: "removed"
    )
    expect(result).to be_success
  end

  def project_all(resource_id)
    event_store.read(
      Coordinator::Write::StreamFactory.new.resource(resource_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[ResourceRegistered ResourceBound ResourceUnbound],
        maximum_count: 10,
        direction: :asc
      )
    ).each { projector.call(_1) }
  end
end
