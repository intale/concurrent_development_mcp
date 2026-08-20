# frozen_string_literal: true

RSpec.describe Coordinator::Mcp::SettingsLoader do
  subject(:loader) { described_class.new }

  it "normalizes explicit allow lists and the bounded request size" do
    settings = loader.call(
      "MCP_ALLOWED_HOSTS" => "api, localhost,api",
      "MCP_ALLOWED_ORIGINS" => "https://example.test",
      "MCP_MAX_REQUEST_BYTES" => "1048576"
    )

    expect(settings.to_h).to eq(
      allowed_hosts: [ "api", "localhost" ],
      allowed_origins: [ "https://example.test" ],
      max_request_bytes: 1_048_576
    )
  end

  it "rejects invalid request-size configuration through dry-validation" do
    expect do
      loader.call("MCP_MAX_REQUEST_BYTES" => "0")
    end.to raise_error(ArgumentError, /MCP settings are invalid/)
  end
end
