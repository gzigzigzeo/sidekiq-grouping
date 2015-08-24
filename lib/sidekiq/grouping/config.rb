module Sidekiq
  module Grouping
    module Config
      include ActiveSupport::Configurable

      # Queue size overflow check polling interval
      config_accessor :poll_interval
      self.config.poll_interval = 3

      # Maximum batch size
      config_accessor :max_batch_size
      self.config.max_batch_size = 1000

      # Batch queue flush lock timeout
      config_accessor :lock_ttl
      self.config.lock_ttl = 1
    end
  end
end
