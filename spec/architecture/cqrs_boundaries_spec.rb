# frozen_string_literal: true

RSpec.describe "CQRS source boundaries" do
  SIDE_ROOT = Rails.root.join("lib/coordinator")

  FORBIDDEN_DEPENDENCIES = {
    shared: [
      "Coordinator::Write",
      "Coordinator::Read",
      "Coordinator::Processes",
      "Coordinator::Mcp",
      "ApplicationRecord",
      "ActiveRecord"
    ],
    write: [
      "Coordinator::Read",
      "Coordinator::Processes",
      "Coordinator::Mcp",
      "ApplicationRecord",
      "ActiveRecord",
      "Coordinator::Container"
    ],
    read: [
      "Coordinator::Write::Commands",
      "Coordinator::Write::Domain",
      "Coordinator::Write::Operations",
      "Coordinator::Write::EventStore",
      "PgEventstore.client",
      "Coordinator::Container"
    ],
    processes: [
      "Coordinator::Read",
      "ApplicationRecord",
      "ActiveRecord",
      "Coordinator::Write::EventFactory",
      "Coordinator::Container"
    ],
    mcp: [
      "PgEventstore",
      "ApplicationRecord",
      "ActiveRecord",
      "Coordinator::Write::Domain",
      "Coordinator::Write::Events",
      "Coordinator::Write::EventStore"
    ]
  }.freeze

  it "keeps each side in its matching Zeitwerk namespace" do
    violations = FORBIDDEN_DEPENDENCIES.keys.flat_map do |side|
      side_files(side).filter_map do |path|
        next if path.basename.to_s == "#{side}.rb"
        source = path.read
        compact_namespace = "module Coordinator::#{side.to_s.camelize}"
        nested_namespace = /module Coordinator\n\s+module #{side.to_s.camelize}/
        next if source.include?(compact_namespace) || source.match?(nested_namespace)

        path.relative_path_from(Rails.root).to_s
      end
    end

    expect(violations).to be_empty,
      "files outside their side namespace: #{violations.join(', ')}"
  end

  it "enforces the allowed one-way dependency graph" do
    violations = FORBIDDEN_DEPENDENCIES.flat_map do |side, forbidden_names|
      side_files(side).flat_map do |path|
        source = path.read
        forbidden_names.filter_map do |name|
          next unless source.include?(name)

          "#{path.relative_path_from(Rails.root)} references #{name}"
        end
      end
    end

    expect(violations).to be_empty, violations.join("\n")
  end

  it "keeps projection models exclusively under Coordinator::Read" do
    model_files = Rails.root.glob("app/models/coordinator/read/**/*.rb")

    expect(model_files).not_to be_empty
    expect(model_files).to all(satisfy { _1.read.include?("module Coordinator::Read") })
    expect(Rails.root.glob("app/models/coordinator/read_models/**/*.rb")).to be_empty
  end

  it "mirrors isolated Coordinator logic in RBS without requiring Rails adapter signatures" do
    implementation_signatures = Rails.root.glob("lib/coordinator/**/*.rb")
      .map { signature_path_for(_1, root: "lib") }
      .uniq
      .sort
    declared_signatures = Rails.root.glob("sig/coordinator/**/*.rbs").filter_map do |path|
      signature = path.relative_path_from(Rails.root).to_s
      signature if implementation_signatures.include?(signature)
    end.sort

    expect(declared_signatures).to eq(implementation_signatures)
  end

  it "keeps every concrete event definition registered under its exact current contract" do
    definitions = Coordinator::Write::EventSchemaRegistry::DEFAULT_DEFINITIONS
    unregistered = SIDE_ROOT.glob("write/events/*.rb").flat_map do |path|
      next [] if path.basename.to_s == "base.rb"

      namespace = path.relative_path_from(Rails.root.join("lib")).sub_ext("").to_s.camelize.constantize
      classes = namespace.is_a?(Class) ? [ namespace ] : namespace.constants(false).map { namespace.const_get(_1, false) }
      classes.select { _1.is_a?(Class) && _1 < Coordinator::Write::Events::Base }.filter_map do |event_class|
        contract = [ event_class.event_type, event_class.schema_version ]
        event_class.name unless definitions[contract] == event_class
      end
    end

    expect(unregistered).to be_empty,
      "unregistered event definitions: #{unregistered.join(', ')}"
  end

  def side_files(side)
    SIDE_ROOT.glob("#{side}/**/*.rb")
  end

  def signature_path_for(path, root:)
    relative = path.relative_path_from(Rails.root.join(root)).sub_ext(".rbs")
    Rails.root.join("sig", relative).relative_path_from(Rails.root).to_s
  end
end
