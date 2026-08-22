# frozen_string_literal: true

RSpec.describe Coordinator::Shared::CompoundMarkerBuilder do
  subject(:builder) { described_class.new }

  it "derives one order-independent compound marker from normalized components" do
    definition = Coordinator::Shared::CompoundMarkerDefinitionV1.new(
      purpose: "localized-description",
      components: [ "resource:description", "locale:en", "resource:description" ]
    )

    result = builder.call(definition)

    expect(result.components).to eq([ "locale:en", "resource:description" ])
    expect(result.digest).to eq(
      "sha256:3fcbfd0045d3a9158afc51da2c5cfe106b06faae5867cc1ae617983ce7e1f4ad"
    )
    expect(result.marker).to eq("compound:localized-description:v1:#{result.digest}")
    expect(
      builder.call(
        Coordinator::Shared::CompoundMarkerDefinitionV1.new(
          purpose: "localized-description",
          components: [ "locale:en", "resource:description" ]
        )
      )
    ).to eq(result)
  end

  it "includes purpose in the compound identity" do
    components = [ "locale:en", "resource:description" ]

    first = builder.call(Coordinator::Shared::CompoundMarkerDefinitionV1.new(purpose: "first", components:))
    second = builder.call(Coordinator::Shared::CompoundMarkerDefinitionV1.new(purpose: "second", components:))

    expect(first.digest).not_to eq(second.digest)
  end

  it "rejects a nested compound marker through the strict dry value schema" do
    expect do
      Coordinator::Shared::CompoundMarkerDefinitionV1.new(
        purpose: "nested",
        components: [ "locale:en", "compound:other:v1:sha256:abc" ]
      )
    end.to raise_error(Dry::Struct::Error)
  end
end
