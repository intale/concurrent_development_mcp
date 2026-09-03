# frozen_string_literal: true

RSpec.describe "Repository EVENTS-02 facts" do
  it "allows a repository registration without a repository key" do
    event = Coordinator::Write::Events::RepositoryRegisteredV2.new(
      repository_id: "018f0f4d-4e45-7abc-8def-000000000001",
      scope: "project:alpha",
      repository_key: nil
    )

    expect(event.repository_key).to be_nil
  end

  it "allows a display name to be cleared explicitly" do
    event = Coordinator::Write::Events::RepositoryDisplayNameChangedV1.new(
      repository_id: "018f0f4d-4e45-7abc-8def-000000000001",
      display_name: nil
    )

    expect(event.display_name).to be_nil
  end
end
