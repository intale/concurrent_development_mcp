# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projections::Skills, :read_model do
  let(:heads) { Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :skill_id ]) }
  let(:revisions) { Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :skill_id, :revision ]) }
  let(:assets) { Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :skill_id, :revision, :path ]) }
  let(:fold) { described_class.new(heads:, revisions:, assets:) }
  let(:models) { [ Coordinator::Read::Skill, Coordinator::Read::SkillRevision, Coordinator::Read::SkillAsset ] }
  let(:registration_time) { Time.utc(2026, 9, 1, 12) }
  let(:publication_time) { registration_time + 60 }

  it "persists a thousand independent publications through compatible masks and reuses stable rows" do
    sources = Array.new(1000) { |index| publication_source(index) }
    sources.each { fold.apply(_1) }
    statements = []
    ActiveSupport::Notifications.subscribed(->(*args) { statements << args.last.fetch(:sql) }, "sql.active_record") do
      persist
    end
    identities = Coordinator::Read::SkillRevision.pluck(:skill_id, :id).to_h

    persist

    expect(models.map(&:count)).to eq([ 1000, 1000, 1000 ])
    expect(Coordinator::Read::SkillRevision.pluck(:skill_id, :id).to_h).to eq(identities)
    expect(statements.count { _1.start_with?("UPDATE") }).to be_between(3, 4)
    expect(Coordinator::Read::SkillRevision.distinct.pluck(:asset_count)).to eq([ 1 ])
    expect(Coordinator::Read::Skill.distinct.pluck(:created_at)).to eq([ registration_time ])
    expect(Coordinator::Read::Skill.distinct.pluck(:updated_at)).to eq([ publication_time ])
  end

  it "uses the authoritative representation count and supports a publication with no assets" do
    source = publication_source(0).merge(asset_count: 0, assets: [])
    fold.apply(source)

    persist

    expect(Coordinator::Read::SkillRevision.sole.asset_count).to eq(0)
    expect(Coordinator::Read::SkillAsset.count).to eq(0)
  end

  def persist
    ApplicationRecord.transaction do
      models.zip([ heads, revisions, assets ]).each do |model, patches|
        Coordinator::Read::Repositories::BatchWriter.new(model:, patches:).call
      end
    end
  end

  def publication_source(index)
    id, revision_id = SecureRandom.uuid_v7, SecureRandom.uuid_v7
    metadata = Coordinator::Write::Metadata::SkillPublicationV3.new(
      command_id: "skill-fold-#{index}", actor_kind: "agent", actor_id: "publisher", recorded_by: "coordinator",
      policy_version: "skill-repository/v2", content_digest: "sha256:#{'a' * 64}"
    )
    event = ProjectionEventFactory.build(
      payload: Coordinator::Write::Events::SkillRevisionPublishedV3.new(skill_id: id, skill_revision_id: revision_id, revision: 1),
      stream: Coordinator::Write::StreamFactory.new.skill(id), stream_revision: 1, global_position: index + 1,
      metadata:, policy_version: "skill-repository/v2", created_at: publication_time
    )
    { skill_id: id, skill_revision_id: revision_id, name: "skill-#{index}", scope: "project:bulk", revision: 1,
      description: "Review", instructions: "Review the change", asset_count: 1,
      assets: [ { path: "SKILL.md", executable: false, media_type: "text/markdown", content_encoding: "utf-8",
        content_text: "Skill content", content_base64: nil, content_sha256: "sha256:#{'b' * 64}", byte_size: 13 } ],
      content_digest: metadata.content_digest, registered_at: registration_time, published_event: event }
  end
end
