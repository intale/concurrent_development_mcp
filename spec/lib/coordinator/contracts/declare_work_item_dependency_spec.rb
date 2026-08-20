# frozen_string_literal: true

RSpec.describe Coordinator::Contracts::DeclareWorkItemDependency do
  subject(:contract) { described_class.new }

  let(:valid_input) do
    {
      "command_id" => "cmd-230",
      "actor" => { "kind" => "agent", "id" => "planner-1" },
      "change_set_id" => "CS-100",
      "dependency_id" => "DEP-1",
      "producer_work_item_id" => "W-100",
      "consumer_work_item_id" => "W-200",
      "dependency_kind" => "requires_candidate",
      "required_output" => nil
    }
  end

  it "normalizes null and structured required-output variants" do
    without_output = contract.call(valid_input)
    with_output = contract.call(
      valid_input.merge(
        "dependency_kind" => "requires_artifact",
        "required_output" => { "kind" => "artifact", "key" => "openapi-v1" }
      )
    )

    expect(without_output).to be_success
    expect(without_output.to_h.fetch(:required_output)).to be_nil
    expect(with_output).to be_success
    expect(with_output.to_h.fetch(:required_output)).to eq(kind: "artifact", key: "openapi-v1")
  end

  it "rejects unknown top-level and nested fields" do
    top_level = contract.call(valid_input.merge("unknown" => true))
    nested = contract.call(
      valid_input.merge("required_output" => { "kind" => "artifact", "key" => "schema", "extra" => true })
    )

    expect(top_level).to be_failure
    expect(top_level.errors.to_h).to have_key(:unknown)
    expect(nested).to be_failure
    expect(nested.errors.to_h.dig(:required_output)).to have_key(:extra)
  end

  it "rejects invalid identifiers and unsupported dependency kinds" do
    result = contract.call(
      valid_input.merge(
        "dependency_id" => "DEP 1",
        "producer_work_item_id" => "?",
        "dependency_kind" => "whenever"
      )
    )

    expect(result).to be_failure
    expect(result.errors.to_h.keys).to include(:dependency_id, :producer_work_item_id, :dependency_kind)
  end
end
