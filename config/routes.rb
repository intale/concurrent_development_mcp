Rails.application.routes.draw do
  mount Coordinator::Container["mcp.transport"] => "/mcp"
  post "graphql" => "graphql#execute"
  root "coordinator_ui#show"
  get "projects" => "coordinator_ui#show"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  mount PgEventstore::Web::Application, at: "/eventstore"
end
