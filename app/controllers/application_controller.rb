# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Configure the application-wide cache to use for AI generated results
  before_action :configure_cache

  private

  def configure_cache
    # Ensure we have a proper cache configuration for storing AI results
    Rails.cache ||= ActiveSupport::Cache::MemoryStore.new(expires_in: 1.hour)
  end
end