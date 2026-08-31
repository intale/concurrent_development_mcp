# frozen_string_literal: true

RSpec.describe "Coordinator UI shell" do
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "mounts the standalone React client from Rails at the project route" do
    session.get "/projects"
    response = session.response

    expect(response.status).to eq(200)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include(
      'id="coordinator-ui-root"',
      'data-react-class="CoordinatorApp"',
      'data-react-props="{}"',
      'type="module" src="http://localhost:5173/@vite/client"',
      'type="module" src="http://localhost:5173/src/main.tsx"'
    )
    expect(response.body).not_to include("data-hydrate")
  end

  it "mounts the same client shell at the application root" do
    session.get "/"
    response = session.response

    expect(response.status).to eq(200)
    expect(response.body).to include('data-react-class="CoordinatorApp"')
  end
end
