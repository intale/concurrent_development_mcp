# frozen_string_literal: true

RSpec.describe Coordinator::Read::Web::ProjectReference do
  subject(:project_reference) { described_class.new }

  it "exposes the exact readable scope rather than an opaque serialized document" do
    scope = "project:concurrent_development_mcp"

    expect(project_reference.encode(scope:)).to eq(scope)
    expect(project_reference.decode(scope)).to eq(scope)
  end

  it "preserves case, Unicode, reserved characters and scope distinctions" do
    [ "project:København/研发:alpha", "work", "project:work", "Project:Work", "home:a%2Fb?#" ].each do |scope|
      expect(project_reference.decode(project_reference.encode(scope:))).to eq(scope)
    end
  end

  it "rejects invalid scopes without decoding or silently normalizing them" do
    [ "", " project:alpha", "project:alpha\n", "x" * 501 ].each do |scope|
      expect { project_reference.encode(scope:) }
        .to raise_error(described_class::InvalidReference, "project scope is invalid")
      expect { project_reference.decode(scope) }
        .to raise_error(described_class::InvalidReference, "project scope is invalid")
    end
  end
end
