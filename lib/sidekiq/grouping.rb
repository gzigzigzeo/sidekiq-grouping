# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/string"
require "active_support/configurable"
require "active_support/core_ext/numeric/time"
require "sidekiq"
require "sidekiq/grouping/version"
require "concurrent"

module Sidekiq
  module Grouping
    autoload :Config, "sidekiq/grouping/config"
    autoload :Redis, "sidekiq/grouping/redis"
    autoload :Batch, "sidekiq/grouping/batch"
    autoload :Middleware, "sidekiq/grouping/middleware"
    autoload :Flusher, "sidekiq/grouping/flusher"
    autoload :FlusherObserver, "sidekiq/grouping/flusher_observer"

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
        @task = Concurrent::TimerTask.new(
          execution_interval: interval
        ) { Sidekiq::Grouping::Flusher.new.flush }
        @task.add_observer(@observer)
        logger.info(
          "[Sidekiq::Grouping] Started polling batches every " \
          "#{interval} seconds"
        )
        @task.execute
      end
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

  config.on(:startup) do
    Sidekiq::Grouping.start!
  end
end
