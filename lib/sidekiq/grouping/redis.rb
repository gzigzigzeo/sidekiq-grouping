# frozen_string_literal: true

require_relative "./redis_dispatcher"

module Sidekiq
  module Grouping
    class Redis
      include RedisDispatcher

      PLUCK_SCRIPT_GTE_6_2_0 = <<-SCRIPT
        local pluck_values = redis.call('lpop', KEYS[1], ARGV[1]) or {}
        if #pluck_values > 0 then
          redis.call('srem', KEYS[2], unpack(pluck_values))
        end
        return pluck_values
      SCRIPT

      PLUCK_SCRIPT_LT_6_2_0 = <<-SCRIPT
        local pluck_values = redis.call('lrange', KEYS[1], 0, ARGV[1] - 1)
        redis.call('ltrim', KEYS[1], ARGV[1], -1)
        for k, v in pairs(pluck_values) do
          redis.call('srem', KEYS[2], v)
        end
        return pluck_values
      SCRIPT

      def push_msg(name, msg, remember_unique: false)
        redis do |conn|
          conn.multi do |pipeline|
            sadd = pipeline.respond_to?(:sadd?) ? :sadd? : :sadd
            redis_connection_call(pipeline, sadd, ns("batches"), name)
            redis_connection_call(pipeline, :rpush, ns(name), msg)

            if remember_unique
              redis_connection_call(
                pipeline, sadd, unique_messages_key(name), msg
              )
            end
          end
        end
      end

      def enqueued?(name, msg)
        member = redis_call(:sismember, unique_messages_key(name), msg)
        return member if member.is_a?(TrueClass) || member.is_a?(FalseClass)

        member != 0
      end

      def batch_size(name)
        redis_call(:llen, ns(name))
      end

      def batches
        redis_call(:smembers, ns("batches"))
      end

      def pluck(name, limit)
        if new_redis_client?
          redis_call(
            :eval,
            pluck_script,
            2,
            ns(name),
            unique_messages_key(name),
            limit
          )
        else
          keys = [ns(name), unique_messages_key(name)]
          args = [limit]
          redis_call(:eval, pluck_script, keys, args)
        end
      end

      def get_last_execution_time(name)
        redis_call(:get, ns("last_execution_time:#{name}"))
      end

      def set_last_execution_time(name, time)
        redis_call(
          :set, ns("last_execution_time:#{name}"), time.to_json
        )
      end

      def lock(name)
        redis_call(
          :set,
          ns("lock:#{name}"),
          "true",
          nx: true,
          ex: Sidekiq::Grouping::Config.lock_ttl
        )
      end

      def delete(name)
        redis do |conn|
          redis_connection_call(conn, :del, ns("last_execution_time:#{name}"))
          redis_connection_call(conn, :del, ns(name))
          redis_connection_call(conn, :srem, ns("batches"), name)
        end
      end

      private

      def unique_messages_key(name)
        ns("#{name}:unique_messages")
      end

      def ns(key = nil)
        "batching:#{key}"
      end

      #
      # The optimized LUA SCRIPT works from Redis greater than or equal to 6.2.
      # Check Redis version in use and return the suitable PLUCK_SCRIPT
      #
      # @return [<Type>] <description>
      #
      def pluck_script
        redis_version = Sidekiq.redis { |conn| conn.info["redis_version"] }
        if Gem::Version.new(redis_version) >= Gem::Version.new("6.2.0")
          PLUCK_SCRIPT_GTE_6_2_0
        else
          PLUCK_SCRIPT_LT_6_2_0
        end
      end
    end
  end
end
