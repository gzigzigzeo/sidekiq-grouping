require 'active_support/core_ext/string'
require 'active_support/configurable'
require 'active_support/core_ext/numeric/time'

require 'sidekiq/batching/config'
require 'sidekiq/batching/redis'
require 'sidekiq/batching/batch'
require 'sidekiq/batching/middleware'
require 'sidekiq/batching/logging'
require 'sidekiq/batching/actor'
require 'sidekiq/batching/supervisor'
require 'sidekiq/batching/version'

module Sidekiq
  module Batching
    class << self
      attr_writer :logger

      def logger
        @logger ||= Sidekiq.logger
      end
    end
  end
end

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Batching::Middleware
  end
end

Sidekiq.configure_server do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Batching::Middleware
  end
end

if Sidekiq.server?
  Sidekiq::Batching::Supervisor.run!
end