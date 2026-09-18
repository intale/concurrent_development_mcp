# frozen_string_literal: true

RSpec.describe "pg_eventstore configuration" do
  it "keeps the source and migration target on distinct test databases" do
    source_uri = URI.parse(PgEventstore.config(:default).pg_uri)
    target_uri = URI.parse(PgEventstore.config(:migration_target).pg_uri)
    worker = ENV.fetch("TEST_ENV_NUMBER", "")

    expect(PgEventstore.available_configs).to include(:default, :migration_target)
    expect(source_uri.path).to eq("/eventstore#{worker}_test")
    expect(target_uri.path).to eq("/eventstore#{worker}_migration_target_test")
    expect(target_uri).not_to eq(source_uri)
  end
end
