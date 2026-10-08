# frozen_string_literal: true

RSpec.describe "pg_eventstore configuration" do
  it "uses only the isolated default test database for each parallel runner" do
    uri = URI.parse(PgEventstore.config.pg_uri)
    worker = ENV.fetch("TEST_ENV_NUMBER", "")

    expect(PgEventstore.available_configs).to eq([ :default ])
    expect(uri.path).to eq("/eventstore#{worker}_test")
  end
end
