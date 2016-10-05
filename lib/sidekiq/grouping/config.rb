module Sidekiq::Grouping::Config
  include ActiveSupport::Configurable

  # Queue size overflow check polling interval
  config_accessor :poll_interval
  config.poll_interval = 3

  # Maximum batch size
  config_accessor :max_batch_size
  config.max_batch_size = 1000

  # Batch queue flush lock timeout
  config_accessor :lock_ttl
  config.lock_ttl = 1
end
