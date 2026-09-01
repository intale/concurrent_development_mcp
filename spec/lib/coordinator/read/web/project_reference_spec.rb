# frozen_string_literal: true

RSpec.describe Coordinator::Read::Web::ProjectReference do
  subject(:project_reference) { described_class.new }

  let(:scope) { "project:København/研发:alpha" }

  it "round-trips an exact coordination scope through an opaque versioned reference" do
    reference = project_reference.encode(scope:)

    expect(project_reference.decode(reference)).to eq(scope)
    expect(JSON.parse(Base64.urlsafe_decode64(reference))).to eq(
      "schema" => "project-reference/v1",
      "scope" => scope
    )
  end

  it "encodes the same exact scope deterministically" do
    expect(project_reference.encode(scope:)).to eq(project_reference.encode(scope:))
  end

  it "rejects malformed, padded, and noncanonical references" do
    canonical = project_reference.encode(scope:)
    noncanonical = Base64.urlsafe_encode64(
      JSON.generate("scope" => scope, "schema" => described_class::SCHEMA_VERSION),
      padding: false
    )

    expect { project_reference.decode("not-base64!") }
      .to raise_error(described_class::InvalidReference, "project reference is invalid")
    expect { project_reference.decode("#{canonical}=") }
      .to raise_error(described_class::InvalidReference, "project reference is invalid")
    expect { project_reference.decode(noncanonical) }
      .to raise_error(described_class::InvalidReference, "project reference is invalid")
  end

  it "rejects references with another version or additional payload fields" do
    wrong_version = encode_document("schema" => "project-reference/v2", "scope" => scope)
    extra_field = encode_document(
      "schema" => described_class::SCHEMA_VERSION,
      "scope" => scope,
      "repository_id" => "018f0f4d-4e45-7abc-8def-000000000041"
    )

    expect { project_reference.decode(wrong_version) }
      .to raise_error(described_class::InvalidReference, "project reference is invalid")
    expect { project_reference.decode(extra_field) }
      .to raise_error(described_class::InvalidReference, "project reference is invalid")
  end

  it "applies the exact project-scope contract while encoding and decoding" do
    invalid_scopes = [ "", " project:alpha", "project:alpha\n", "x" * 501 ]

    invalid_scopes.each do |invalid_scope|
      expect { project_reference.encode(scope: invalid_scope) }
        .to raise_error(described_class::InvalidReference, "project scope is invalid")
      expect do
        project_reference.decode(
          encode_document("schema" => described_class::SCHEMA_VERSION, "scope" => invalid_scope)
        )
      end.to raise_error(described_class::InvalidReference, "project reference is invalid")
    end
  end

  def encode_document(document)
    canonical = Coordinator::Shared::CanonicalJson.new.encode(document)
    Base64.urlsafe_encode64(canonical, padding: false)
  end
end
