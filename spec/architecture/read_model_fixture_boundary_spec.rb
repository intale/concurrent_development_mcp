# frozen_string_literal: true

RSpec.describe "Read-model test fixture boundaries", :read_model do
  FACTORY_ROOT = Rails.root.join("spec/factories")
  FORBIDDEN_FACTORY_REFERENCES = {
    write_side: "Coordinator::Write",
    process: "Coordinator::Processes",
    projector: "Coordinator::Read::Projectors",
    subscription: "Coordinator::Read::Subscriptions",
    event_store: "PgEventstore"
  }.freeze
  FORBIDDEN_FACTORY_CALLBACK = /\b(?:after|before|callback|to_create)\s*(?:\(|\{)/
  QUERY_FIXTURE_CROSSING = Regexp.union(
    /Coordinator::Read::Projectors::/,
    /Coordinator::Container\["projectors\./,
    /Coordinator::Write::Operations::/,
    /PgEventstore\.client/,
    /\b[A-Z][A-Za-z0-9]*Scenario\.new/
  )
  REQUEST_FIXTURE_CROSSING = Regexp.union(
    /Coordinator::Read::Projectors::/,
    /Coordinator::Container\["projectors\./
  )

  it "provides a valid namespaced read-side factory" do
    factory = FactoryBot.factories[:coordinator_read_attempt_history]

    expect(factory.build_class).to eq(Coordinator::Read::AttemptHistory)
    expect { FactoryBot.lint([ factory ]) }.not_to raise_error
  end

  it "keeps factories callback-free and isolated from write/process/projection behavior" do
    violations = factory_files.flat_map do |path|
      source = path.read
      references = FORBIDDEN_FACTORY_REFERENCES.filter_map do |boundary, constant|
        boundary if source.include?(constant)
      end
      references << :callback if source.match?(FORBIDDEN_FACTORY_CALLBACK)

      references.map { "#{relative(path)}: #{_1}" }
    end

    expect(violations).to be_empty, violations.join("\n")
  end

  it "requires every namespaced factory to declare its class in the mirrored directory" do
    violations = factory_files.filter_map do |path|
      source = path.read
      declarations = source.scan(/factory\s+:\w+,\s*class:\s*["']([^"']+)["']/).flatten
      next "#{relative(path)}: missing explicit class" if declarations.empty?

      declarations.filter_map do |class_name|
        expected_directory = FACTORY_ROOT.join(class_name.deconstantize.underscore)
        "#{relative(path)}: expected under #{relative(expected_directory)}" unless path.dirname == expected_directory
      end
    end.flatten

    expect(violations).to be_empty, violations.join("\n")
  end

  it "keeps the phased migration inventory complete and mapped to one bounded owner" do
    inventory = ReadModelFixtureMigrationInventory
    paths = inventory::ALL

    expect(inventory::BY_TARGET_BOUNDARY.transform_values(&:length)).to eq(
      factory_bot_read: 21,
      direct_event_projector: 16,
      split_transport: 13,
      subscription_contract_with_cucumber_delivery: 1
    )
    expect(paths.length).to eq(paths.uniq.length)
    expect(paths).to all(satisfy { Rails.root.join(_1).file? })
  end

  it "rejects new non-Cucumber write-to-read fixture crossings during migration" do
    inventory = ReadModelFixtureMigrationInventory
    dual_store_specs = spec_files.filter_map do |path|
      declaration = path.each_line.first(10).join
      relative(path) if declaration.include?(":event_store") && declaration.include?(":read_model")
    end
    fixture_crossings = crossing_paths

    expect(dual_store_specs).to match_array(inventory::LEGACY_FULL_CHAIN)
    expect(fixture_crossings - inventory::LEGACY_FULL_CHAIN).to be_empty,
      "unplanned read-fixture crossings: #{(fixture_crossings - inventory::LEGACY_FULL_CHAIN).join(', ')}"
  end

  def factory_files
    FACTORY_ROOT.glob("coordinator/read/**/*.rb")
  end

  def spec_files
    Rails.root.glob("spec/**/*_spec.rb")
  end

  def crossing_paths
    query_paths = Rails.root.glob("spec/lib/coordinator/read/queries/**/*_spec.rb").filter_map do |path|
      relative(path) if path.read.match?(QUERY_FIXTURE_CROSSING)
    end
    request_paths = Rails.root.glob("spec/requests/**/*_spec.rb").filter_map do |path|
      relative(path) if path.read.match?(REQUEST_FIXTURE_CROSSING)
    end

    (query_paths + request_paths).uniq
  end

  def relative(path)
    path.relative_path_from(Rails.root).to_s
  end
end
