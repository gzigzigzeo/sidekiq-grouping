require 'active_support/core_ext/string'
require 'active_support/configurable'
require 'active_support/core_ext/numeric/time'

require 'sidekiq/grouping/config'
require 'sidekiq/grouping/redis'
require 'sidekiq/grouping/batch'
require 'sidekiq/grouping/middleware'
require 'sidekiq/grouping/logging'
require 'sidekiq/grouping/actor'
require 'sidekiq/grouping/supervisor'
require 'sidekiq/grouping/version'

module Sidekiq
  module Grouping
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
