# frozen_string_literal: true

Capybara.register_driver(:coordinator_headless_firefox) do |app|
  options = Selenium::WebDriver::Firefox::Options.new
  options.binary = ENV.fetch("FIREFOX_BINARY", "/snap/firefox/current/usr/lib/firefox/firefox")
  options.add_argument("-headless")
  options.add_preference("browser.chrome.favicons", false)
  options.add_preference("browser.chrome.site_icons", false)

  service = Selenium::WebDriver::Firefox::Service.new(
    path: ENV.fetch("GECKODRIVER_BINARY", "/snap/bin/geckodriver")
  )

  Capybara::Selenium::Driver.new(
    app,
    browser: :firefox,
    options:,
    service:
  )
end

Capybara.javascript_driver = :coordinator_headless_firefox
Capybara.server = :puma, { Silent: true }
Capybara.default_max_wait_time = 10
