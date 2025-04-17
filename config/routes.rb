# config/routes.rb
Rails.application.routes.draw do
  root 'jobs#index'

  resources :jobs do
    resources :job_forms

    # AJAX routes for form filtering
    get 'localities', to: 'job_forms#localities'
    get 'form_numbers', to: 'job_forms#form_numbers'
  end

  # Admin interface routes
  namespace :admin do
    root to: 'forms#index'  # Changed from 'base#index' to 'forms#index'

    resources :forms do
      member do
        get 'preview_dates'
      end

      resources :calculation_rules
    end

    # JSON export only
    get 'export_json', to: 'forms#export_json'
  end
end