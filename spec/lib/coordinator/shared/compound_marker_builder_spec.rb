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
    expect(result.marker).to eq(
      "compound:localized-description:v2|9:locale=en|20:resource=description"
    )
    expect(result.marker).not_to include(result.digest)
    expect(
      builder.call(
        Coordinator::Shared::CompoundMarkerDefinitionV1.new(
          purpose: "localized-description",
          components: [ "locale:en", "resource:description" ]
        )
      )
    ).to eq(result)
  end

  it "includes purpose in the compound identity and never indexes the digest" do
    components = [ "locale:en", "resource:description" ]

    first = builder.call(Coordinator::Shared::CompoundMarkerDefinitionV1.new(purpose: "first", components:))
    second = builder.call(Coordinator::Shared::CompoundMarkerDefinitionV1.new(purpose: "second", components:))

    expect(first.digest).not_to eq(second.digest)
    expect(first.marker).to start_with("compound:first:v2|")
    expect(second.marker).to start_with("compound:second:v2|")
    expect(first.marker).not_to match(/sha|md5/i)
  end

  it "rejects a nested compound marker through the strict dry value schema" do
    expect do
      Coordinator::Shared::CompoundMarkerDefinitionV1.new(
        purpose: "nested",
        components: [ "locale:en", "compound:other:v2|5:key=a" ]
      )
    end.to raise_error(Dry::Struct::Error)
  end
end
