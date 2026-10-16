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
      scope: "project:ui/shell café",
      repository_key: "ui-shell"
    )
    project_scope = repository.scope
    project_segment = ERB::Util.url_encode(project_scope).gsub("+", "%20").gsub("%3A", ":")
    project_path = "/projects/#{project_segment}"
    paths = [ "/", "/projects", project_path ] +
      [
        "#{project_path}/change-sets",
        "#{project_path}/change-sets/CS-shell",
        "#{project_path}/work-items",
        "#{project_path}/work-items/W-shell",
        "#{project_path}/dependencies",
        "#{project_path}/dependencies/D-shell",
        "#{project_path}/resources",
        "#{project_path}/resources/018f0f4d-4e45-7abc-8def-000000000001",
        "#{project_path}/work-intentions",
        "#{project_path}/work-intentions/018f0f4d-4e45-7abc-8def-000000000002",
        "#{project_path}/skills",
        "#{project_path}/skills/event-modeling",
        "#{project_path}/skills/event-modeling/assets/references/example.md",
        "#{project_path}/artifacts",
        "#{project_path}/artifacts/018f0f4d-4e45-7abc-8def-000000000221",
        "#{project_path}/artifacts/018f0f4d-4e45-7abc-8def-000000000221/relationships",
        "#{project_path}/decisions",
        "#{project_path}/decisions/D-shell",
        "#{project_path}/guidance",
        "#{project_path}/guidance/M-shell",
        "#{project_path}/choices",
        "#{project_path}/choices/CHO-shell",
        "#{project_path}/impacts",
        "#{project_path}/impacts/018f0f4d-4e45-7abc-8def-000000000222",
        "#{project_path}/candidates",
        "#{project_path}/candidates/CAN-shell",
        "#{project_path}/obligations",
        "#{project_path}/obligations/OBL-shell",
        "#{project_path}/merge-snapshots",
        "#{project_path}/merge-snapshots/MS-shell",
        "#{project_path}/release-sets",
        "#{project_path}/release-sets/RS-shell",
        "/audit/command-receipts",
        "/audit/command-receipts/adj.20260826.candidate.1.submit",
        "/skills",
        "/skills/018f0f4d-4e45-7abc-8def-000000000031",
        "/skills/018f0f4d-4e45-7abc-8def-000000000031/assets/references/example.md",
        "/operations/batches",
        "/operations/batches/BATCH-shell"
      ]

    paths.each do |path|
      session.get path

      expect(session.response.status).to eq(200), "#{path} returned #{session.response.status}"
      expect(session.response.media_type).to eq("text/html"), "#{path} was not served as HTML"
      expect(session.response.body).to include('data-react-class="CoordinatorApp"')
    end
  end
end
