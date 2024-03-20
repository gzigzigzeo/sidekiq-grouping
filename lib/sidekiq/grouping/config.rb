# frozen_string_literal: true

module Sidekiq
  module Grouping
    module Config
      include ActiveSupport::Configurable

      def self.options
        if Sidekiq.respond_to?(:[]) # Sidekiq 6.x
          Sidekiq[:grouping] || {}
        elsif Sidekiq.respond_to?(:options) # Sidekiq <= 5.x
          Sidekiq.options[:grouping] || Sidekiq.options["grouping"] || {}
        else # Sidekiq 7.x
          Sidekiq.default_configuration[:grouping] || {}
        end
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

      # Option to override how Sidekiq::Grouping know about tests env
      config_accessor :tests_env do
        options[:tests_env] || (
          defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env.test?
        )
      end
    end
  end
end
