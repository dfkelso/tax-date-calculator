Rails.application.routes.draw do
  root 'jobs#index'

  resources :jobs do
    resources :job_forms

    # AJAX routes for form filtering
    get 'localities', to: 'job_forms#localities'
    get 'form_numbers', to: 'job_forms#form_numbers'
  end
end