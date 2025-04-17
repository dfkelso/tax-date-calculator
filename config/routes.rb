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
    root to: 'base#index'

    resources :forms do
      member do
        get 'preview_dates'
      end

      resources :calculation_rules
    end

    # JSON export/import
    get 'export_json', to: 'base#export_json'
    post 'import_json', to: 'base#import_json'
  end
end