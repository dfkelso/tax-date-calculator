# config/initializers/cache_store.rb
Rails.application.configure do
  # Configure the default cache store
  config.cache_store = :memory_store, { size: 64.megabytes }

  # Set a longer expiration for AI-generated rules (1 week)
  config.ai_rules_expiration = 1.week
end