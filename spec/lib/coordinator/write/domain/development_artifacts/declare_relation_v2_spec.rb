# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::DevelopmentArtifacts::DeclareRelationV2 do
  let(:source_artifact_id) { SecureRandom.uuid_v7 }
  let(:target_artifact_id) { SecureRandom.uuid_v7 }
  let(:relation) do
    Coordinator::Write::DevelopmentArtifacts::RelationBuilder.new.call(
      source_artifact_id:,
      relation: "references",
      target: Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
        kind: "artifact",
        id: target_artifact_id,
        status: "verified"
      ),
      attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(
        path: "docs/target.md"
      )
    )
  end

  it "writes declaration and supersession to independent relation streams" do
    first = described_class.new.call(relation:).value!
    previous_state = Coordinator::Write::Domain::DevelopmentArtifacts::RelationStateV2.reduce(
      [ first.event_plan.events.first ]
    )
    replacement = Coordinator::Write::DevelopmentArtifacts::RelationBuilder.new.call(
      source_artifact_id:,
      relation: "references",
      target: Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
        kind: "artifact", id: SecureRandom.uuid_v7, status: "verified"
      ),
      attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(path: "docs/replacement.md")
    )
    result = described_class.new.call(
      relation: replacement,
      source_relations: [previous_state],
      superseded_state: previous_state,
      superseded_relation_id: relation.relation_id,
      supersession_reason: "Target was replaced"
    ).value!

    expect(result.event_plan.writes.map { _1.stream.stream_name }).to eq(
      %w[DevelopmentArtifactRelation DevelopmentArtifactRelation]
    )
    expect(result.event_plan.events.map(&:class)).to eq(
      [
        Coordinator::Write::Events::DevelopmentArtifactRelationDeclaredV2,
        Coordinator::Write::Events::DevelopmentArtifactRelationSupersededV2
      ]
    )
    expect(result.event_plan.events.map(&:to_h).join).not_to include("declared_at", "superseded_at")
    expect(result.event_plan.events.first.to_h).to include(
      relation_id: replacement.relation_id,
      source_artifact_id: replacement.source_artifact_id,
      target_kind: "artifact",
      target_id: replacement.target.id,
      path: "docs/replacement.md"
    )
  end

  it "returns an existing decision for the same directed natural tuple" do
    first = described_class.new.call(relation:).value!
    state = Coordinator::Write::Domain::DevelopmentArtifacts::RelationStateV2.reduce(
      [ first.event_plan.events.first ]
    )

    result = described_class.new.call(relation:, source_relations: [ state ]).value!

    expect(result.outcome).to eq("existing")
    expect(result.relation_id).to eq(relation.relation_id)
    expect(result.event_plan).to be_nil
  end

  it "rejects a natural tuple whose existing relation was superseded" do
    first = described_class.new.call(relation:).value!
    declaration = first.event_plan.events.first
    supersession = Coordinator::Write::Events::DevelopmentArtifactRelationSupersededV2.new(
      relation_id: relation.relation_id,
      source_artifact_id: source_artifact_id,
      replacement_relation_id: SecureRandom.uuid_v7,
      reason: "obsolete"
    )
    state = Coordinator::Write::Domain::DevelopmentArtifacts::RelationStateV2.reduce(
      [ declaration, supersession ]
    )

    result = described_class.new.call(relation:, source_relations: [ state ])

    expect(result).to be_failure
    expect(result.failure.code).to eq(:development_artifact_relation_superseded)
    expect(result.failure.details).to eq(
      artifact_id: source_artifact_id,
      relation_id: relation.relation_id,
      replacement_relation_id: supersession.replacement_relation_id
    )
    expect(
      Coordinator::Write::Tasks::DomainErrorV1::Type[
        code: result.failure.code.to_s,
        message: result.failure.message,
        details: result.failure.details
      ]
    ).to be_a(Coordinator::Write::Tasks::DomainErrorV1::DevelopmentArtifactRelationSupersededError)
  end

  it "rejects supersession without an authoritative relation state" do
    missing_relation_id = SecureRandom.uuid_v7
    result = described_class.new.call(
      relation:,
      superseded_relation_id: missing_relation_id,
      supersession_reason: "obsolete"
    )

    expect(result).to be_failure
    expect(result.failure.code).to eq(:development_artifact_relation_not_found)
    expect(result.failure.details).to eq(
      artifact_id: source_artifact_id,
      relation_id: missing_relation_id
    )
    expect(
      Coordinator::Write::Tasks::DomainErrorV1::Type[
        code: result.failure.code.to_s,
        message: result.failure.message,
        details: result.failure.details
      ]
    ).to be_a(Coordinator::Write::Tasks::DomainErrorV1::DevelopmentArtifactRelationNotFoundError)
  end

  it "reports complete typed details when a relation has already been superseded" do
    first = described_class.new.call(relation:).value!
    declaration = first.event_plan.events.first
    supersession = Coordinator::Write::Events::DevelopmentArtifactRelationSupersededV2.new(
      relation_id: relation.relation_id,
      source_artifact_id: source_artifact_id,
      replacement_relation_id: SecureRandom.uuid_v7,
      reason: "obsolete"
    )
    state = Coordinator::Write::Domain::DevelopmentArtifacts::RelationStateV2.reduce(
      [ declaration, supersession ]
    )
    replacement = Coordinator::Write::DevelopmentArtifacts::RelationBuilder.new.call(
      source_artifact_id:,
      relation: "references",
      target: Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
        kind: "artifact", id: SecureRandom.uuid_v7, status: "verified"
      ),
      attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(path: "docs/new.md")
    )

    result = described_class.new.call(
      relation: replacement,
      source_relations: [ state ],
      superseded_state: state,
      superseded_relation_id: relation.relation_id,
      supersession_reason: "another replacement"
    )

    expect(result).to be_failure
    expect(result.failure.details).to eq(
      artifact_id: source_artifact_id,
      relation_id: relation.relation_id,
      existing_replacement_relation_id: supersession.replacement_relation_id,
      requested_replacement_relation_id: replacement.relation_id
    )
    expect(
      Coordinator::Write::Tasks::DomainErrorV1::Type[
        code: result.failure.code.to_s,
        message: result.failure.message,
        details: result.failure.details
      ]
    ).to be_a(Coordinator::Write::Tasks::DomainErrorV1::DevelopmentArtifactRelationAlreadySupersededError)
  end

  it "reports both relation kinds when supersession is not allowed" do
    first = described_class.new.call(relation:).value!
    state = Coordinator::Write::Domain::DevelopmentArtifacts::RelationStateV2.reduce(
      [ first.event_plan.events.first ]
    )
    replacement = Coordinator::Write::DevelopmentArtifacts::RelationBuilder.new.call(
      source_artifact_id:,
      relation: "contains",
      target: Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
        kind: "artifact", id: SecureRandom.uuid_v7, status: "verified"
      ),
      attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(path: "docs/new.md")
    )

    result = described_class.new.call(
      relation: replacement,
      source_relations: [ state ],
      superseded_state: state,
      superseded_relation_id: relation.relation_id,
      supersession_reason: "wrong relation kind"
    )

    expect(result).to be_failure
    expect(result.failure.details).to eq(
      artifact_id: source_artifact_id,
      relation_id: relation.relation_id,
      relation: "references",
      requested_relation: "contains"
    )
    expect(
      Coordinator::Write::Tasks::DomainErrorV1::Type[
        code: result.failure.code.to_s,
        message: result.failure.message,
        details: result.failure.details
      ]
    ).to be_a(Coordinator::Write::Tasks::DomainErrorV1::DevelopmentArtifactRelationSupersessionNotAllowedError)
  end

  it "reports complete typed details when active relation capacity is reached" do
    states = Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT.times.map do
      candidate = Coordinator::Write::DevelopmentArtifacts::RelationBuilder.new.call(
        source_artifact_id:,
        relation: "references",
        target: Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
          kind: "external", id: "https://example.test/#{SecureRandom.uuid_v7}", status: "unverified"
        ),
        attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(path: nil)
      )
      state_event = described_class.new.call(relation: candidate).value!.event_plan.events.first
      Coordinator::Write::Domain::DevelopmentArtifacts::RelationStateV2.reduce([ state_event ])
    end

    result = described_class.new.call(relation:, source_relations: states)

    expect(result).to be_failure
    expect(result.failure.details).to eq(
      artifact_id: source_artifact_id,
      limit_kind: "active",
      active_count: Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT,
      active_maximum: Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT,
      active_remaining: 0,
      lifetime_count: Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT,
      lifetime_maximum: Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT,
      lifetime_remaining: Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT -
        Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT
    )
    expect(
      Coordinator::Write::Tasks::DomainErrorV1::Type[
        code: result.failure.code.to_s,
        message: result.failure.message,
        details: result.failure.details
      ]
    ).to be_a(Coordinator::Write::Tasks::DomainErrorV1::DevelopmentArtifactRelationLimitReachedError)
  end
end
