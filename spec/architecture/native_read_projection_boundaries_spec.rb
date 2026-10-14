# frozen_string_literal: true

RSpec.describe "Native Read projection boundaries" do
  it "has no Read delivery ledger or incoming-event contracts" do
    expect(Rails.root.join("app/models/coordinator/read/processed_projection_event.rb")).not_to exist
    expect(Dir.glob(Rails.root.join("lib/coordinator/read/contracts/*source_event.rb"))).to be_empty
    expect(Coordinator::Container.keys).not_to include("repositories.processed_projection_events")
  end

  it "keeps folds and their adapters independent of source validators and delivery claims" do
    files = Dir.glob(Rails.root.join("lib/coordinator/read/{projectors,projections}/**/*.rb"))
    forbidden = /EventSchemaRegistry|ProcessedProjectionEvents|\.claim\(|Dry::Validation/
    violations = files.select { forbidden.match?(File.read(_1)) }
    expect(violations).to be_empty
  end
end
