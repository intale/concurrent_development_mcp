# frozen_string_literal: true

RSpec.describe Coordinator::Write::Tasks::TargetContractRegistry do
  subject(:contracts) { described_class::CONTRACTS }

  let(:mutation_tools) do
    Coordinator::Mcp::ToolRegistry.all.select { _1 < Coordinator::Mcp::MutationTool }
  end

  it "is exhaustive across public mutation tools and target input documents" do
    expect(contracts.map(&:tool_name)).to contain_exactly(*mutation_tools.map(&:tool_name))
    expect(described_class.input_document_classes).to contain_exactly(
      *Coordinator::Write::CommandInputDocuments::TARGET_TYPES
    )
    expect(contracts.map(&:tool_name).uniq.length).to eq(contracts.length)

    contracts.each do |contract|
      admitted_tool_names = contract.input_document_class.schema.key(:tool_name).type.values
      expect(admitted_tool_names).to include(contract.tool_name)
    end
  end

  it "binds every target document to a real builder and every command to a real executor" do
    builder = Coordinator::Write::Tasks::TargetCommandBuilder.new
    executor = Coordinator::Write::Tasks::TargetExecutor.new(
      event_store: Coordinator::Write::EventStore.new(client: PgEventstore.client)
    )

    contracts.each do |contract|
      expect(builder.private_methods).to include(contract.builder_method)
      expect(executor.instance_variable_get(contract.executor_variable)).to respond_to(:call_command)
    end
  end

  it "publishes the exact success receipt shape and the strict error catalog per tool" do
    mutation_tools.each do |tool|
      contract = described_class.fetch(tool.tool_name)
      data_variants = tool.to_h.dig(:outputSchema, :properties, :data, :oneOf)
      receipt_schema, error_schema = data_variants

      expect(receipt_schema.fetch(:required)).to contain_exactly(
        *contract.receipt_class.schema.keys.map { _1.name.to_s }
      )
      expect(error_schema.dig(:properties, :code, :enum)).to contain_exactly(
        *Coordinator::Write::Tasks::DomainErrorV1::ERROR_CODES.map(&:to_s)
      )
    end
  end
end
