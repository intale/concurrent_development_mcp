# frozen_string_literal: true

RSpec.describe "Projects UI shell" do
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

  it "serves the same client shell at the root and coordination routes" do
    [ "/", "/projects/018f0f4d-4e45-7abc-8def-000000000011/coordination" ].each do |path|
      session.get path

      expect(session.response.status).to eq(200)
      expect(session.response.body).to include('data-react-class="CoordinatorApp"')
    end
  end
end
