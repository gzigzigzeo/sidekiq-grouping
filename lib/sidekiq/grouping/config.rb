module Sidekiq::Grouping::Config
  include ActiveSupport::Configurable

  def self.options
    Sidekiq.options["grouping"] || {}
  end

  # Queue size overflow check polling interval
  config_accessor :poll_interval do
    options[:poll_interval] || 3
  end

  # Maximum batch size
  config_accessor :max_batch_size do
    options[:max_batch_size] || 1000
  end

  # Batch queue flush lock timeout
  config_accessor :lock_ttl do
    options[:lock_ttl] || 1
  end
end
