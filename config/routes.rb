Rails.application.routes.draw do
  mount Coordinator::Container["mcp.transport"] => "/mcp"
  post "graphql" => "graphql#execute"
  root "projects#index"
  get "projects" => "projects#index"
  get "projects/:project_ref" => "projects#index"
  get "projects/:project_ref/*client_path" => "projects#index",
      format: false,
      defaults: { format: :html }
  get "skills" => "projects#index"
  get "skills/*client_path" => "projects#index",
      format: false,
      defaults: { format: :html }
  get "audit/command-receipts" => "projects#index"
  get "audit/command-receipts/:command_id" => "projects#index",
      constraints: { command_id: /[^\/]+/ },
      format: false,
      defaults: { format: :html }
  get "operations/batches" => "projects#index"
  get "operations/batches/:batch_id" => "projects#index",
      constraints: { batch_id: /[^\/]+/ },
      format: false,
      defaults: { format: :html }

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  mount PgEventstore::Web::Application, at: "/eventstore"
end
