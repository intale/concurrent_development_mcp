# frozen_string_literal: true

RSpec.describe "Cucumber public MCP boundary" do
  FEATURE_ROOTS = %w[features/step_definitions features/support].freeze
  FORBIDDEN_DIRECT_CALLS = {
    write_operation: /Coordinator::Write::Operations/,
    process_manager: /Coordinator::Processes::ProcessManagers/,
    projector: /Coordinator::Read::Projectors/,
    event_append: /\b(?:PgEventstore\.client|event_store)\.(?:append|multiple|write)\b/
  }.freeze
  ALLOWED_CONTAINER_REFERENCES = {
    "features/support/live_subscriptions.rb" => [ "Coordinator::Container[factory_key]" ],
    "features/support/candidate_impact_obligation_acceptance_world.rb" =>
      [ 'Coordinator::Container["event_schema_registry"]' ],
    "features/support/mcp_acceptance_world.rb" => [ 'Coordinator::Container["event_schema_registry"]' ]
  }.freeze

  def feature_ruby_files
    FEATURE_ROOTS.flat_map { Dir.glob(Rails.root.join(_1, "**/*.rb")) }.sort
  end

  it "does not let feature code advance the domain behind public MCP" do
    violations = feature_ruby_files.flat_map do |path|
      relative_path = Pathname(path).relative_path_from(Rails.root).to_s
      File.readlines(path).filter_map.with_index(1) do |line, line_number|
        boundary = FORBIDDEN_DIRECT_CALLS.find { |_name, pattern| line.match?(pattern) }&.first
        "#{relative_path}:#{line_number}: #{boundary}" if boundary
      end
    end

    expect(violations).to be_empty, <<~MESSAGE
      Cucumber must advance coordination through HTTP MCP and tasks/get only.
      Move a lower-level assertion to one bounded RSpec responsibility: real pg_eventstore for
      write/process behavior, direct concrete events for projectors, or FactoryBot for read state.
      Keep the complete production write-to-read journey in Cucumber:
      #{violations.join("\n")}
    MESSAGE
  end

  it "limits Container access to subscription lifecycle and passive schema inspection" do
    violations = feature_ruby_files.flat_map do |path|
      relative_path = Pathname(path).relative_path_from(Rails.root).to_s
      allowed = ALLOWED_CONTAINER_REFERENCES.fetch(relative_path, [])

      File.readlines(path).filter_map.with_index(1) do |line, line_number|
        next unless line.include?("Coordinator::Container[")
        next if allowed.any? { line.include?(_1) }

        "#{relative_path}:#{line_number}: #{line.strip}"
      end
    end

    expect(violations).to be_empty, <<~MESSAGE
      Feature code may use Container only for the production subscription-set lifecycle or passive
      event-schema inspection; public coordination behavior must cross HTTP MCP:
      #{violations.join("\n")}
    MESSAGE
  end
end
