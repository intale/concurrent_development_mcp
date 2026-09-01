# frozen_string_literal: true

RSpec.describe "MCP public contract parity" do
  let(:mutation_tools) do
    Coordinator::Mcp::ToolRegistry.all.select { _1 < Coordinator::Mcp::MutationTool }
  end
  let(:query_tools) do
    Coordinator::Mcp::ToolRegistry.all.select { _1 < Coordinator::Mcp::QueryTool }
  end

  it "keeps mutation discovery, Dry actor validation, and Task targets aligned" do
    mutation_tools.each do |tool|
      expect(advertised_actor_kinds(tool)).to eq(contract_actor_kinds(tool)), tool.tool_name
    end

    expect(mutation_tools.map(&:tool_name)).to contain_exactly(
      *Coordinator::Write::Tasks::TargetContractRegistry.tool_names
    )
  end

  it "uses canonical UUIDv7 Repository identities throughout public input discovery" do
    repository_schemas = Coordinator::Mcp::ToolRegistry.all.flat_map do |tool|
      repository_identity_schemas(tool.input_schema.to_h)
    end

    expect(repository_schemas).not_to be_empty
    repository_schemas.each do |schema|
      variants = schema.fetch(:anyOf, [ schema ]).reject { _1[:type] == "null" }
      expect(variants).to all(include(pattern: Coordinator::Mcp::Schemas.uuid_v7.fetch(:pattern)))
    end
  end

  it "advertises UTF-8 byte limits that the Repository Dry contract enforces" do
    schema = Coordinator::Mcp::Schemas.repository_register
    bounded = [
      schema.dig(:properties, :scope),
      schema.dig(:properties, :display_name, :anyOf, 0),
      schema.dig(:properties, :paths, :items),
      schema.dig(:properties, :remotes, :items)
    ]

    expect(bounded).to contain_exactly(
      include("x-encoding": "UTF-8", "x-maxBytes": 500),
      include("x-encoding": "UTF-8", "x-maxBytes": 255),
      include("x-encoding": "UTF-8", "x-maxBytes": 1_024),
      include("x-encoding": "UTF-8", "x-maxBytes": 2_048)
    )
  end

  it "publishes one named strict data contract for every public tool family" do
    mutation_tools.each do |tool|
      contract = Coordinator::Write::Tasks::TargetContractRegistry.fetch(tool.tool_name)
      data_schemas = tool.output_schema.to_h.dig(:properties, :data, :oneOf)
      receipt_schema = data_schemas.find { _1[:title] == contract.receipt_class.name }

      expect(receipt_schema).to include(type: "object", additionalProperties: false), tool.tool_name
      expect(receipt_schema.fetch(:properties).values).not_to include({}), tool.tool_name
      expect(tool.to_h.fetch(:outputSchema)).to eq(tool.output_schema.to_h), tool.tool_name
    end

    expect(query_tools.map(&:tool_name)).to contain_exactly(
      *Coordinator::Mcp::QueryResultSchemas::DATA_CLASSES.keys
    )
    query_tools.each do |tool|
      schemas = tool.output_schema.to_h.dig(:properties, :data, :oneOf)
      expect(schemas).to all(include(type: "object", additionalProperties: false, title: a_string_matching(/\A.+\z/)))
    end
  end

  it "binds every emitted next-action name to its target input schema" do
    Coordinator::Mcp::NextActionSchemas::TARGET_TOOL_NAMES.each do |tool_name|
      action = Coordinator::Mcp::NextActionSchemas.action_schema(tool_name)
      target = Coordinator::Mcp::ToolRegistry.all.find { _1.tool_name == tool_name }

      expect(action.dig(:properties, :tool)).to eq(const: tool_name)
      expect(action.dig(:properties, :arguments)).to eq(
        target.input_schema.to_h.except(:"$schema", "$schema")
      )
    end
  end

  it "keeps the public registry unique while persisted tool names remain identifier-compatible" do
    tool_names = Coordinator::Mcp::ToolRegistry.all.map(&:tool_name)

    expect(tool_names).to eq(tool_names.uniq)
    expect(tool_names).to all(match(Coordinator::Shared::Types::IDENTIFIER_PATTERN))
    expect(Coordinator::Shared::Types::CoordinationToolName["retired_tool_name"])
      .to eq("retired_tool_name")
  end

  it "limits documented dry-operation runtime exemptions to generated call wrappers" do
    query_signatures = Dir[Rails.root.join("sig/coordinator/read/queries/*.rbs")]

    aggregate_failures do
      query_signatures.each do |path|
        signature = File.read(path)
        call_count = signature.scan(/def call:/).length
        documented_exemptions = signature.scan(
          /# dry-operation prepends #call; runtime RBS wrapping recursively re-enters that wrapper\.\n\s+%a\{rbs:test:skip\}\n\s+def call:/
        ).length

        expect(signature.scan("rbs:test:skip").length).to eq(call_count), path
        expect(documented_exemptions).to eq(call_count), path
      end
    end
    expect(File.read(Rails.root.join("sig/coordinator/read/queries/operation_get.rbs"))).to include(
      "def call: (command_input input) -> QueryResultV1"
    )
    expect(File.read(Rails.root.join("sig/coordinator/mcp/query_tool.rbs"))).to include(
      "-> ::MCP::Tool::Response"
    )
  end

  def contract_actor_kinds(tool)
    operation = Coordinator::Container[tool.operation]
    preparer = operation.instance_variable_get(:@preparer)
    owner = preparer.is_a?(Method) ? preparer.receiver : preparer
    contract = owner.instance_variable_get(:@contract)

    Coordinator::Shared::Types::ACTOR_KINDS.select do |kind|
      errors = contract.call(actor: { kind:, id: "contract-parity-agent" }).errors.to_h
      errors.dig(:actor, :kind).nil?
    end.sort
  end

  def advertised_actor_kinds(tool)
    kind = tool.input_schema.to_h.dig(:properties, :actor, :properties, :kind)
    Array(kind[:const] || kind[:enum]).sort
  end

  def repository_identity_schemas(node)
    case node
    when Hash
      properties = node.fetch(:properties, {})
      direct = [ properties[:repository_id] ].compact
      plural = properties[:repository_ids]&.fetch(:items, nil)
      [ *direct, plural, *node.values.flat_map { repository_identity_schemas(_1) } ].compact
    when Array
      node.flat_map { repository_identity_schemas(_1) }
    else
      []
    end
  end
end
