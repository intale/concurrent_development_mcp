# frozen_string_literal: true

RSpec.describe "production deployment preflight" do
  it "fails clearly when the chosen environment file cannot be read" do
    environment = { "PRODUCTION_ENV_FILE" => Rails.root.join("tmp", "missing-production-env-#{SecureRandom.uuid_v7}").to_s }
    _, error, status = Open3.capture3(environment, Rails.root.join("bin/deploy-production").to_s)
    expect(status.exitstatus).to eq(64)
    expect(error).to include("from config/production.env.example first")
  end

  it "rejects unsafe project names before creating a deployment lock or running Compose" do
    environment = { "PRODUCTION_ENV_FILE" => "/dev/null", "PRODUCTION_COMPOSE_PROJECT" => "../unsafe-project" }
    _, error, status = Open3.capture3(environment, Rails.root.join("bin/deploy-production").to_s)
    expect(status.exitstatus).to eq(64)
    expect(error).to include("valid lowercase Compose project name")
  end
end
