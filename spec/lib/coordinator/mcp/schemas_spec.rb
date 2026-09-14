# frozen_string_literal: true

RSpec.describe Coordinator::Mcp::Schemas do
  it "advertises independent Candidate-file and work-intention resource boundaries" do
    intention_set = described_class.work_intention_set_declare
    intention_set_maximum = intention_set
      .dig(:properties, :resources, :maxItems)
    candidate_maximum = described_class.candidate_submit
      .dig(:properties, :change_manifest, :properties, :files, :maxItems)

    expect(intention_set_maximum).to eq(Coordinator::Shared::Types::WRITE_SET_RESOURCE_MAXIMUM_COUNT)
    expect(candidate_maximum).to eq(Coordinator::Shared::Types::CANDIDATE_MANIFEST_MAXIMUM_FILE_COUNT)
    expect(candidate_maximum).to be > intention_set_maximum
    expect(intention_set.dig(:properties, :resources, :items, :properties, :mode)).to include(
      default: "shared",
      enum: %w[shared exclusive]
    )
    expect(intention_set.dig(:properties, :ttl_seconds)).to include(minimum: 30, maximum: 3_600)
  end

  it "publishes only the work-intention command vocabulary" do
    names = Coordinator::Mcp::ToolRegistry.all.map(&:tool_name)

    expect(names).to include(
      "work_intention_set_declare",
      "work_intention_set_expand",
      "work_intention_set_renew",
      "work_intention_set_withdraw"
    )
    expect(names).not_to include("write_set_reserve", "write_set_expand", "lease_renew", "lease_release")
  end

  it "requires one exact scope and bounds the Repository discovery cursor" do
    schema = described_class.repository_list

    expect(schema.fetch(:required)).to eq([ "scope" ])
    expect(schema.dig(:properties, :scope)).to include(
      type: "string",
      minLength: 1,
      maxLength: 500
    )
    expect(schema.dig(:properties, :after_repository_id, :anyOf).first).to include(
      type: "string",
      pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
    )
    expect(schema.dig(:properties, :limit, :anyOf).first).to include(
      type: "integer",
      minimum: 1,
      maximum: 100
    )
  end

  it "bounds coordination and extensible Decision discovery without freshness inputs" do
    coordination = described_class.coordination_list
    decision_list = described_class.decision_list
    resolution = described_class.decision_resolve

    expect(coordination.fetch(:required)).to eq([ "scope" ])
    expect(coordination.dig(:properties, :limit, :anyOf).first).to include(
      maximum: Coordinator::Shared::Types::COORDINATION_DISCOVERY_MAXIMUM_ITEMS
    )
    expect(coordination.fetch(:properties).keys).not_to include(
      :fresh,
      :minimum_revision,
      :projection_status
    )
    expect(decision_list.fetch(:required)).to eq([ "repository_id" ])
    expect(decision_list.dig(:properties, :repository_id)).to eq(described_class.uuid_v7)
    expect(decision_list.dig(:properties, :limit, :anyOf).first).to include(
      maximum: Coordinator::Shared::Types::DECISION_DISCOVERY_MAXIMUM_ITEMS
    )
    expect(resolution.dig(:properties, :topic_id)).to eq(described_class.identifier)
    expect(
      resolution.dig(:properties, :context, :properties, :phase, :enum)
    ).to eq(Coordinator::Shared::Types::DECISION_PHASES)
  end

  it "lets Skill and Skill-asset reads pin one immutable projected revision" do
    [ described_class.skill_get, described_class.skill_asset_get ].each do |schema|
      expect(schema.dig(:properties, :revision, :anyOf).first).to include(
        type: "integer",
        minimum: 1
      )
      expect(schema.fetch(:required)).not_to include("revision")
    end
  end

  it "accepts the granular Decision-partition facts used to bind merge authorization" do
    variants = described_class.merge_authorization_request
      .dig(:properties, :expected_impact_policy, :anyOf)
      .find { _1[:type] == "object" }
      .dig(:properties, :partition_event, :anyOf)

    expect(variants.map { _1.dig(:properties, :type, :const) }).to contain_exactly(
      "DecisionPartitionAdvanced",
      "DecisionAddedToPartition",
      "DecisionRemovedFromPartition"
    )
  end

  it "reserves internal labels and coordinator-owned UUIDv7 identities in every public mutation schema" do
    mutation_tools = Coordinator::Mcp::ToolRegistry.all.select do |tool|
      tool < Coordinator::Mcp::MutationTool
    end

    expect(mutation_tools).not_to be_empty
    mutation_tools.each do |tool|
      schemas = command_id_schemas(tool.input_schema.to_h)
      expect(schemas).not_to be_empty, "#{tool.tool_name} has no command_id schema"
      schemas.each do |schema|
        pattern = Regexp.new(schema.fetch(:pattern))
        expect("cmd-public").to match(pattern), tool.tool_name
        expect("internal:lease-expiry:v1:client-supplied").not_to match(pattern), tool.tool_name
        expect("0198c000-0000-7000-8000-000000000001").not_to match(pattern), tool.tool_name
      end
    end
  end

  def command_id_schemas(node)
    case node
    when Hash
      current = node.fetch(:properties, {}).fetch(:command_id, nil)
      [ current, *node.values.flat_map { command_id_schemas(_1) } ].compact
    when Array
      node.flat_map { command_id_schemas(_1) }
    else
      []
    end
  end
end
