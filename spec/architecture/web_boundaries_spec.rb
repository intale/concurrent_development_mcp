# frozen_string_literal: true

RSpec.describe "Read-only web boundaries" do
  GRAPHQL_ROOT = Rails.root.join("app/graphql/coordinator/web/graphql")
  UI_ROOT = Rails.root.join("ui")

  it "keeps Rails API-only and GraphQL query-only" do
    definition = Coordinator::Web::Graphql::Schema.to_definition

    expect(Rails.application.config.api_only).to be(true)
    expect(definition).to include("type Query")
    expect(definition).not_to match(/^type (?:Mutation|Subscription)\b/)
  end

  it "keeps GraphQL as an adapter over semantic read queries" do
    forbidden = %w[
      Coordinator::Mcp Coordinator::Write PgEventstore ApplicationRecord ActiveRecord
    ]
    violations = GRAPHQL_ROOT.glob("**/*.rb").flat_map do |path|
      forbidden.filter_map do |constant|
        "#{path.relative_path_from(Rails.root)} references #{constant}" if path.read.include?(constant)
      end
    end

    query_source = GRAPHQL_ROOT.join("types/query_type.rb").read
    expect(query_source).to include("Coordinator::Read::Queries::RepositoryList")
    expect(query_source).to include("Coordinator::Read::Web::Queries::CoordinationDashboard")
    expect(violations).to be_empty, violations.join("\n")
  end

  it "keeps dashboard reads on projections and UI scenarios on FactoryBot fixtures" do
    semantic_sources = Rails.root.glob("lib/coordinator/read/web/**/*.rb").map(&:read).join("\n")
    cucumber_steps = Rails.root.join("features/step_definitions/coordination_dashboard_steps.rb").read
    schema = Rails.root.join("db/structure.sql").read

    expect(semantic_sources).not_to include("Coordinator::Write", "Coordinator::Mcp", "PgEventstore")
    expect(cucumber_steps).to include("FactoryBot.create", "FactoryBot.build")
    expect(cucumber_steps).not_to match(/submit_and_(?:execute|await)|call_tool|event_store|subscription/i)
    expect(schema).to include(
      "CREATE VIEW public.coordination_dashboard_work_items",
      "CREATE VIEW public.coordination_dashboard_change_sets",
      "CREATE VIEW public.coordination_dashboard_dependencies"
    )
  end

  it "keeps Rails GraphQL adapters outside runtime RBS assertions" do
    typed_runner = Rails.root.join("bin/rspec").read

    expect(typed_runner).not_to include("Coordinator::Web")
    expect(Rails.root.join("sig/coordinator/web/graphql/delivery_browser_cursor.rbs")).not_to exist
    expect(Rails.root.join("sig/coordinator/web/graphql/types/delivery_types.rbs")).not_to exist
  end

  it "keeps the browser on GraphQL and away from MCP and mutation operations" do
    skip "UI source is introduced by ui-01" unless UI_ROOT.directory?

    sources = UI_ROOT.glob("src/**/*.{ts,tsx,graphql}").map(&:read).join("\n")
    expect(sources).to include("/graphql")
    expect(sources).not_to include("/mcp")
    expect(sources).not_to match(/\b(?:mutation|subscription)\b/i)
  end

  it "uses Yarn and the official AdminLTE React Bootstrap template without a competing style system" do
    package = JSON.parse(UI_ROOT.join("package.json").read)

    expect(package.fetch("packageManager")).to start_with("yarn@")
    expect(package.fetch("dependencies")).to include(
      "@adminlte/react" => "0.6.1",
      "bootstrap" => "5.3.8",
      "bootstrap-icons" => "1.13.1"
    )
    expect(package.fetch("dependencies").keys).not_to include(
      "@mui/material", "@mui/x-data-grid", "@emotion/react", "@emotion/styled", "next"
    )
    expect(package.fetch("devDependencies").keys).not_to include("next")
    expect(UI_ROOT.join("yarn.lock")).to exist
    expect(UI_ROOT.join("package-lock.json")).not_to exist
    expect(UI_ROOT.glob("src/**/*.css")).to be_empty
    sources = UI_ROOT.glob("{src,test}/**/*.{ts,tsx}").map(&:read).join("\n")
    expect(sources).not_to match(%r{(?:from|import)\s*[('"].*next(?:/|['"])}i)
    expect(UI_ROOT.join("src/main.tsx").read).to include("@adminlte/react/css")
    expect(UI_ROOT.join("src/app.tsx").read).to include("app-wrapper", "app-sidebar", "app-main")
    expect(UI_ROOT.join("src/projects/project-catalog-page.tsx").read).to include(
      "app-content-header", "app-content"
    )
  end

  it "uses the official react-rails mount without a custom integration controller" do
    vite = UI_ROOT.join("vite.config.ts").read
    layout = Rails.root.join("app/views/layouts/application.html.erb").read
    view = Rails.root.join("app/views/projects/index.html.erb").read
    entrypoint = UI_ROOT.join("src/main.tsx").read
    package = JSON.parse(UI_ROOT.join("package.json").read)

    expect(Rails.application.config.api_only).to be(true)
    expect(ProjectsController.superclass).to eq(ActionController::Base)
    expect(vite).to include(
      'base: "/ui/"',
      'outDir: "../public/ui"',
      'entryFileNames: "coordinator-ui.js"',
      '? "coordinator-ui.css"'
    )
    expect(layout).to include(
      'stylesheet_link_tag "/ui/coordinator-ui.css"',
      'javascript_include_tag "/ui/coordinator-ui.js", type: "module"'
    )
    expect(view).to include('react_component("CoordinatorApp"', "prerender: false")
    expect(view).not_to include('id="root"')
    expect(entrypoint).to include('from "react_ujs"', "ReactRailsUJS.getConstructor")
    expect(entrypoint).not_to include("createRoot")
    expect(package.fetch("dependencies")).to include("react_ujs" => "3.3.1")
    expect(Bundler.locked_gems.specs.map(&:name)).to include("react-rails")
    expect(Rails.root.join("app/controllers/coordinator_ui_controller.rb")).not_to exist
    expect(Rails.root.join(".gitignore").read).to include("/public/ui/")
  end
end
