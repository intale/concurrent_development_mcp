# frozen_string_literal: true

RSpec.describe "Coordinator identity boundaries" do
  RUNTIME_ROOT = Rails.root.join("lib/coordinator")
  DIGEST_IDENTITY_PATTERN = /(?:Digest::|OpenSSL::Digest|hexdigest|\.sha256\(|sha256:)/
  LEGACY_DIGEST_ID_PATTERN = /(?:skill|artifact|artifact-observation|artifact-relation):v1:[0-9a-f]{64}/

  it "keeps identity, stream, and indexed marker construction free of digest functions" do
    violations = identity_and_index_sources.filter_map do |path|
      next unless path.read.match?(DIGEST_IDENTITY_PATTERN)

      path.relative_path_from(Rails.root).to_s
    end

    expect(violations).to be_empty,
      "digest-backed identity or marker construction found in: #{violations.join(', ')}"
  end

  it "keeps removed digest-backed Skill and Development Artifact identities out of runtime code" do
    violations = RUNTIME_ROOT.glob("**/*.rb").filter_map do |path|
      next unless path.read.match?(LEGACY_DIGEST_ID_PATTERN)

      path.relative_path_from(Rails.root).to_s
    end

    expect(violations).to be_empty,
      "legacy digest-backed identities found in: #{violations.join(', ')}"
  end

  it "accepts only UUIDv7 Skill and Development Artifact stream identities" do
    types = [
      Coordinator::Shared::Types::SkillId,
      Coordinator::Shared::Types::DevelopmentArtifactId,
      Coordinator::Shared::Types::DevelopmentArtifactObservationId,
      Coordinator::Shared::Types::DevelopmentArtifactRelationId
    ]

    types.each do |type|
      expect(type[SecureRandom.uuid_v7]).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
      expect { type["artifact:v1:#{'a' * 64}"] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  def identity_and_index_sources
    patterns = [
      "**/*identity_builder.rb",
      "**/*_id_builder.rb",
      "**/*marker_builder.rb",
      "**/*stream_factory.rb",
      "shared/resource_marker_codec.rb",
      "shared/markers/**/*.rb"
    ]

    patterns.flat_map { RUNTIME_ROOT.glob(_1) }.uniq.reject do |path|
      path == RUNTIME_ROOT.join("shared/compound_marker_builder.rb")
    end
  end
end
