# frozen_string_literal: true

RSpec.describe "production asset configuration" do
  it "requires revalidation of the stable standalone React entry assets" do
    environment = {
      "RAILS_ENV" => "production", "RUBYOPT" => nil,
      "SECRET_KEY_BASE" => "production-asset-spec-not-a-deployment-secret",
      "DATABASE_HOST" => "pgbouncer", "DATABASE_USERNAME" => "coordinator",
      "DATABASE_PASSWORD" => "configuration-spec"
    }
    script = "puts JSON.generate(Rails.application.config.public_file_server.headers)"
    output, error, status = Open3.capture3(environment, RbConfig.ruby, "bin/rails", "runner", script, chdir: Rails.root)

    expect(status).to be_success, error
    expect(JSON.parse(output)).to include("cache-control" => "public, max-age=0, must-revalidate")
  end
end
