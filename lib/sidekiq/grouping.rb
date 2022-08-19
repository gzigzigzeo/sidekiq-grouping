require "active_support"
require "active_support/core_ext/string"
require "active_support/configurable"
require "active_support/core_ext/numeric/time"
require "sidekiq/grouping/version"
require "concurrent"

module Sidekiq::Grouping
  autoload :Config, "sidekiq/grouping/config"
  autoload :Redis, "sidekiq/grouping/redis"
  autoload :Batch, "sidekiq/grouping/batch"
  autoload :ReliableBatch, "sidekiq/grouping/reliable_batch"
  autoload :Middleware, "sidekiq/grouping/middleware"
  autoload :Flusher, "sidekiq/grouping/flusher"
  autoload :FlusherObserver, "sidekiq/grouping/flusher_observer"
  autoload :Lazarus, "sidekiq/grouping/lazarus"

  class << self
    attr_writer :logger

    def logger
      @logger ||= Sidekiq.logger
    end

    def force_flush_for_test!
      Sidekiq::Grouping::Flusher.new.force_flush_for_test!
    end

    def start!
      interval = Sidekiq::Grouping::Config.poll_interval
      @observer = Sidekiq::Grouping::FlusherObserver.new
      @task = Concurrent::TimerTask.new(execution_interval: interval) do
        Sidekiq::Grouping::Flusher.new.flush
        Sidekiq::Grouping::Lazarus.new.revive if Sidekiq::Grouping::Config.reliable
      end
      @task.add_observer(@observer)
      logger.info(
        "[Sidekiq::Grouping] Started polling batches every #{interval} seconds"
      )
      @task.execute
    end
  end
end

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Grouping::Middleware
  end
end

Sidekiq.configure_server do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Grouping::Middleware
  end
end

Sidekiq::Grouping.start! if Sidekiq.server?
