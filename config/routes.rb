Rails.application.routes.draw do
  namespace :api do
    post "/login", to: "sessions#login"
    post "/refresh", to: "sessions#refresh"
    delete "/logout", to: "sessions#logout"
    get "/profile", to: "profiles#show"
    resources :dynamic_tables do
      resources :dynamic_fields, only: [ :index, :create ]
      resources :dynamic_records, only: [ :index, :create, :update, :destroy ]
    end
    namespace :v1 do
      # 记录CRUD路由
      get "/:identifier", to: "dynamic_api#index"
      post "/:identifier", to: "dynamic_api#create"
      get "/:identifier/:id", to: "dynamic_api#show"
      put "/:identifier/:id", to: "dynamic_api#update"
      patch "/:identifier/:id", to: "dynamic_api#update"
      delete "/:identifier/:id", to: "dynamic_api#destroy"
    end
  end
  root "pages#home"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
  # 兜底，给前端React
  get "*path", to: "pages#home", constraints: ->(req) { !req.xhr? && req.format.html? }
end
