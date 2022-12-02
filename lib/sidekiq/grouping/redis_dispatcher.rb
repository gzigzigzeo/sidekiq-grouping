# frozen_string_literal: true

module Sidekiq
  module Grouping
    module RedisDispatcher
      def redis_call(command, *args, **kwargs)
        redis do |connection|
          redis_connection_call(connection, command, *args, **kwargs)
        end
      end

      def redis_connection_call(connection, command, *args, **kwargs)
        if new_redis_client? # redis-client
          connection.call(command.to_s.upcase, *args, **kwargs)
        else # redis
          connection.public_send(command, *args, **kwargs)
        end
      end

      def new_redis_client?
        Sidekiq::VERSION[0].to_i >= 7
      end

      def redis(&block)
        Sidekiq.redis(&block)
      end
    end
  end
end
