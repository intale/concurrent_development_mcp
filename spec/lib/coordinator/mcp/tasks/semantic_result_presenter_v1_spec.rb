# frozen_string_literal: true

RSpec.describe Coordinator::Mcp::Tasks::SemanticResultPresenterV1 do
  subject(:presenter) { described_class.new }

  it "renders a semantic success into the MCP CallToolResult wire contract" do
    semantic = Coordinator::Write::Tasks::SemanticResultV1::Success.new(
      kind: "success",
      summary: "ChangeSet created",
      command_id: "cmd-present-success",
      receipt: "cmd-present-success",
      data: Coordinator::Write::CommandReceiptData::ChangeSet.new(
        change_set_id: "CS-present-success"
      ),
      warnings: [],
      next_actions: []
    )

    result = presenter.call(semantic)

    expect(result).to have_attributes(isError: false)
    expect(result.structuredContent).to have_attributes(
      status: "ok",
      command_id: semantic.command_id,
      receipt: semantic.receipt,
      data: semantic.data
    )
    expect(JSON.parse(result.content.sole.text)).to eq(
      JSON.parse(JSON.generate(result.structuredContent.to_h))
    )
  end

  it "renders a semantic domain rejection as a completed MCP tool error" do
    error = Coordinator::Write::Tasks::DomainErrorV1::ChangeSetError.new(
      code: "change_set_already_exists",
      message: "ChangeSet already exists",
      details: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetDetails.new(
        change_set_id: "CS-present-denial"
      )
    )
    semantic = Coordinator::Write::Tasks::SemanticResultV1::DomainRejection.new(
      kind: "domain_rejection",
      status: "denied",
      summary: error.message,
      command_id: "cmd-present-denial",
      error:,
      next_actions: []
    )

    result = presenter.call(semantic)

    expect(result).to have_attributes(isError: true)
    expect(result.structuredContent).to have_attributes(
      status: "denied",
      command_id: semantic.command_id,
      receipt: nil,
      data: error
    )
    expect(JSON.parse(result.content.sole.text)).to eq(
      JSON.parse(JSON.generate(result.structuredContent.to_h))
    )
  end
end
