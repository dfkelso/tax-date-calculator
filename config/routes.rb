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
    root to: 'forms#index'

    resources :forms do
      member do
        get 'preview_dates'
        post 'fill_missing_years'
        get 'confirm_missing_years'
        post 'apply_missing_years'
        post 'generate_ai_rules'
        get 'confirm_ai_rules'
        post 'apply_ai_rules'
      end

      resources :calculation_rules
    end

    # JSON export only
    get 'export_json', to: 'forms#export_json'
    post 'import_json', to: 'base#import_json'
  end
end