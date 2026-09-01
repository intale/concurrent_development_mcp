# frozen_string_literal: true

RSpec.describe "Projects UI shell", :read_model do
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "mounts the official react-rails component from the conventional project route" do
    session.get "/projects"
    response = session.response

    expect(response.status).to eq(200)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include(
      'id="coordinator-ui-root"',
      'data-react-class="CoordinatorApp"',
      'data-react-props="{}"',
      'rel="stylesheet" href="/ui/coordinator-ui.css"',
        'src="/ui/coordinator-ui.js" type="module"'
    )
    expect(response.body).not_to include("data-hydrate", "@vite/client", ".vite/manifest.json")
  end

  it "serves the same client shell at every client-side project route" do
    repository = create(
      :coordinator_read_repository,
      scope: "project:ui-shell",
      repository_key: "ui-shell"
    )
    project_ref = Coordinator::Read::Web::ProjectReference.new.encode(scope: repository.scope)
    project_path = "/projects/#{project_ref}"
    paths = [ "/", "/projects", project_path ] +
      %w[coordination resources knowledge governance delivery].map { "#{project_path}/#{_1}" } +
      [
        "#{project_path}/coordination/change-sets/CS-shell",
        "#{project_path}/resources/inventory",
        "#{project_path}/resources/inventory/018f0f4d-4e45-7abc-8def-000000000001",
        "#{project_path}/resources/leases",
        "#{project_path}/resources/leases/018f0f4d-4e45-7abc-8def-000000000002",
        "#{project_path}/knowledge/skills",
        "#{project_path}/knowledge/skills/event-modeling",
        "#{project_path}/knowledge/skills/event-modeling/assets/references/example.md",
        "#{project_path}/knowledge/artifacts",
        "#{project_path}/knowledge/artifacts/artifact:v1:#{'a' * 64}",
        "#{project_path}/knowledge/artifacts/artifact:v1:#{'a' * 64}/relationships",
        "/audit/command-receipts",
        "/audit/command-receipts/CMD-shell",
        "/operations/batches",
        "/operations/batches/BATCH-shell"
      ]

    paths.each do |path|
      session.get path, headers: { "ACCEPT" => "text/html" }

      expect(session.response.status).to eq(200), "#{path} returned #{session.response.status}"
      expect(session.response.body).to include('data-react-class="CoordinatorApp"')
    end
  end
end
