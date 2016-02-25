require 'active_support/core_ext/string'
require 'active_support/configurable'
require 'active_support/core_ext/numeric/time'
require 'sidekiq/grouping/version'
require 'celluloid/current'

module Sidekiq
  module Grouping
    autoload :Config, 'sidekiq/grouping/config'
    autoload :Redis, 'sidekiq/grouping/redis'
    autoload :Batch, 'sidekiq/grouping/batch'
    autoload :Middleware, 'sidekiq/grouping/middleware'
    autoload :Logging, 'sidekiq/grouping/logging'
    autoload :Actor, 'sidekiq/grouping/actor'
    autoload :Supervisor, 'sidekiq/grouping/supervisor'

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
    chain.add Sidekiq::Grouping::Middleware
  end
end

Sidekiq.configure_server do |config|
  config.client_middleware do |chain|
    chain.add Sidekiq::Grouping::Middleware
  end
end

if Sidekiq.server?
  Sidekiq::Grouping::Supervisor.run!
end
