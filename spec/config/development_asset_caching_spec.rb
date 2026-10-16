# frozen_string_literal: true

RSpec.describe "development asset configuration" do
  it "prevents storage of static JavaScript and CSS while retaining the controller cache toggle" do
    environment = { "RAILS_ENV" => "development", "RUBYOPT" => nil }
    script = <<~RUBY
      assets = { "entry.js" => "console.log('current build');", "entry.css" => "body { color: black; }" }
      responses = Dir.mktmpdir("development-asset-cache") do |directory|
        assets.each { |name, content| File.write(File.join(directory, name), content) }
        handler = ActionDispatch::Static.new(
          Rails.application, directory,
          headers: Rails.application.config.public_file_server.headers
        )
        request = Rack::MockRequest.new(handler)
        assets.to_h do |name, _content|
          response = request.get("/" + name)
          [ name, { status: response.status, cache_control: response["cache-control"], body: response.body } ]
        end
      end
      puts JSON.generate(
        responses: responses,
        controller_caching: Rails.application.config.action_controller.perform_caching,
        cache_flag: Rails.root.join("tmp/caching-dev.txt").exist?
      )
    RUBY
    output, error, status = Open3.capture3(
      environment, RbConfig.ruby, "-rtmpdir", "-rjson", "bin/rails", "runner", script, chdir: Rails.root
    )

    expect(status).to be_success, error
    result = JSON.parse(output)
    expect(result.fetch("controller_caching")).to eq(result.fetch("cache_flag"))
    expect(result.fetch("responses")).to eq(
      "entry.js" => { "status" => 200, "cache_control" => "no-store", "body" => "console.log('current build');" },
      "entry.css" => { "status" => 200, "cache_control" => "no-store", "body" => "body { color: black; }" }
    )
  end
end
