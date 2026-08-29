# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::PublishSkillRevision do
  subject(:contract) { described_class.new }

  it "accepts a bounded complete skill revision with passive assets" do
    result = contract.call(valid_input)

    expect(result).to be_success
    expect(result.to_h.dig(:assets, 0, :executable)).to be(false)
  end

  it "rejects unsafe paths, duplicate paths, and noncanonical binary Base64" do
    result = contract.call(
      valid_input(
        assets: [
          asset(path: "../secrets"),
          asset(path: "scripts/run.sh"),
          asset(
            path: "scripts/run.sh",
            content: {
              encoding: "binary",
              media_type: "application/octet-stream",
              base64: "YQ=\n"
            }
          )
        ]
      )
    )

    expect(result).to be_failure
    expect(result.errors.to_h).to have_key(:assets)
  end

  it "keeps name and scope exact while rejecting ambiguous surrounding whitespace" do
    result = contract.call(valid_input(name: " deploy ", scope: " project:alpha "))

    expect(result).to be_failure
    expect(result.errors.to_h).to include(:name, :scope)
  end

  def valid_input(**overrides)
    {
      command_id: "cmd-skill-1",
      actor: { kind: "agent", id: "agent-1" },
      name: "deploy",
      scope: "project:alpha",
      expected_revision: 0,
      description: "Deploy the current project",
      instructions: "Validate, package, and deploy the requested revision.",
      assets: [ asset(path: "scripts/run.sh") ]
    }.merge(overrides)
  end

  def asset(**overrides)
    {
      path: "scripts/run.sh",
      executable: false,
      content: {
        encoding: "utf-8",
        media_type: "text/x-shellscript",
        text: "#!/bin/sh\nexit 0\n"
      }
    }.merge(overrides)
  end
end
