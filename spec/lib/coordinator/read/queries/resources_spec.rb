# frozen_string_literal: true

RSpec.describe "Resource discovery queries", :read_model do
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000010" }
  let(:resource_ids) do
    %w[
      018f0f4d-4e45-7abc-8def-000000000011
      018f0f4d-4e45-7abc-8def-000000000012
      018f0f4d-4e45-7abc-8def-000000000013
    ]
  end

  it "gets the latest available lifecycle state and pages a Repository in UUID order" do
    create(
      :coordinator_read_resource,
      :inactive,
      resource_id: resource_ids.fetch(0),
      repository_id:,
      normalized_path: "app/models/query_one.rb"
    )
    create(
      :coordinator_read_resource,
      resource_id: resource_ids.fetch(1),
      repository_id:,
      normalized_path: "app/models/query_two.rb"
    )
    create(
      :coordinator_read_resource,
      resource_id: resource_ids.fetch(2),
      repository_id:,
      kind: "directory",
      normalized_path: "app/services"
    )

    inactive = Coordinator::Read::Queries::ResourceGet.new.call(
      resource_id: resource_ids.fetch(0)
    ).value!
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
    expect((first_page.items + second_page.items).map(&:resource_id)).to eq(resource_ids)

    filtered = query.call(repository_id:, kind: "file", lifecycle_status: "current").value!.data.page
    expect(filtered.items.map(&:resource_id)).to eq([ resource_ids.fetch(1) ])
  end

  it "returns typed absent and invalid results" do
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
end
