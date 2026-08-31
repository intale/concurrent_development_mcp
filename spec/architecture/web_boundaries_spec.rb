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
    expect(violations).to be_empty, violations.join("\n")
  end

  it "mirrors every namespaced GraphQL implementation in RBS" do
    implementations = GRAPHQL_ROOT.glob("**/*.rb").map do |path|
      relative = path.relative_path_from(Rails.root.join("app/graphql")).sub_ext(".rbs")
      Rails.root.join("sig", relative).relative_path_from(Rails.root).to_s
    end.sort
    signatures = Rails.root.glob("sig/coordinator/web/graphql/**/*.rbs").map do |path|
      path.relative_path_from(Rails.root).to_s
    end.sort

    expect(signatures).to eq(implementations)
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

  it "mounts fingerprinted static production assets through a Rails-owned HTML shell" do
    vite = UI_ROOT.join("vite.config.ts").read
    layout = Rails.root.join("app/views/layouts/coordinator_ui.html.erb").read
    view = Rails.root.join("app/views/coordinator_ui/show.html.erb").read
    controller = Rails.root.join("app/controllers/coordinator_ui_controller.rb").read
    entrypoint = UI_ROOT.join("src/main.tsx").read
    package = JSON.parse(UI_ROOT.join("package.json").read)

    expect(Rails.application.config.api_only).to be(true)
    expect(CoordinatorUiController.superclass).to eq(ActionController::Base)
    expect(vite).to include('base: "/ui/"', "manifest: true", 'outDir: "../public/ui"')
    expect(layout).to include('<script type="module"', '<link rel="stylesheet"')
    expect(view).to include('react_component("CoordinatorApp"', "prerender: false")
    expect(view).not_to include('id="root"')
    expect(entrypoint).to include('from "react_ujs"', "ReactRailsUJS.getConstructor")
    expect(entrypoint).not_to include("createRoot")
    expect(package.fetch("dependencies")).to include("react_ujs" => "3.3.1")
    expect(Bundler.locked_gems.specs.map(&:name)).to include("react-rails")
    expect(controller).to include('public/ui/.vite/manifest.json')
    expect(Rails.root.join(".gitignore").read).to include("/public/ui/")
  end
end
