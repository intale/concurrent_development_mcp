# frozen_string_literal: true

RSpec.describe Coordinator::PgStreamFactory do
  subject(:factory) { described_class.new }

  it "maps a domain stream reference through the public pg_eventstore value object" do
    reference = Coordinator::StreamFactory.new.change_set("CS-100")

    stream = factory.call(reference)

    expect(stream).to eq(
      PgEventstore::Stream.new(
        context: "DevelopmentPlanning",
        stream_name: "ChangeSet",
        stream_id: "CS-100"
      )
    )
  end
end
