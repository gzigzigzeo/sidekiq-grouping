module Sidekiq
  module Batching
    module Config
      include ActiveSupport::Configurable

      config_accessor :poll_interval
      self.config.poll_interval = 5

      config_accessor :max_batch_size
      self.config.max_batch_size = 500

      config_accessor :lock_ttl
      self.config.lock_ttl = 1
    end
  end
end