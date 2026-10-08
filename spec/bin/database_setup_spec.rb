# frozen_string_literal: true

RSpec.describe "database setup executable" do
  it "provisions the accepted development store and an isolated migration target through public tasks" do
    contents = Rails.root.join("bin/setup_db").read

    expect(contents).to include(
      'PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore_migration_target_v7" bundle exec rake pg_eventstore:create',
      'PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore_migration_target_v7" bundle exec rake pg_eventstore:migrate',
      'PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore_migration_target" bundle exec rake pg_eventstore:create',
      'PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore_migration_target" bundle exec rake pg_eventstore:migrate'
    )
    expect(contents).not_to include('localhost:5532/eventstore"')
  end
end
