# frozen_string_literal: true

class CoordinatorUiController < ActionController::Base
  layout "coordinator_ui"

  def show
    @coordinator_ui_stylesheets, @coordinator_ui_scripts =
      if Rails.env.production?
        production_assets
      else
        development_assets
      end
  end

  private

  def production_assets
    manifest = JSON.parse(Rails.root.join("public/ui/.vite/manifest.json").read)
    entrypoint = manifest.fetch("index.html")

    [
      Array(entrypoint["css"]).map { |path| "/ui/#{path}" },
      [ "/ui/#{entrypoint.fetch("file")}" ]
    ]
  end

  def development_assets
    origin = ENV.fetch("COORDINATOR_UI_DEV_ORIGIN", "http://localhost:5173")

    [ [], [ "#{origin}/@vite/client", "#{origin}/src/main.tsx" ] ]
  end
end
