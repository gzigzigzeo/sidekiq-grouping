module Sidekiq
  module Grouping
    class Redis

      PLUCK_SCRIPT = <<-SCRIPT
        local pluck_values = redis.call('lpop', KEYS[1], ARGV[1]) or {}
        if #pluck_values > 0 then
          redis.call('srem', KEYS[2], unpack(pluck_values))
        end
        return pluck_values
      SCRIPT

      def push_msg(name, msg, remember_unique = false)
        redis do |conn|
          conn.multi do |transaction|
            transaction.call('SADD', ns("batches"), name)
            transaction.call('RPUSH', ns(name), msg)
            transaction.call('SADD', unique_messages_key(name), msg) if remember_unique
          end
        end
      end

      def enqueued?(name, msg)
        redis do |conn|
          conn.call('SISMEMBER', unique_messages_key(name), msg)
        end
      end

      def batch_size(name)
        redis { |conn| conn.call('LLEN', ns(name)) }
      end

      def batches
        redis { |conn| conn.call('SMEMBERS', ns("batches")) }
      end

      def pluck(name, limit)
        redis { |conn| conn.call('EVAL', PLUCK_SCRIPT, 2, ns(name), unique_messages_key(name), limit) }
      end

      def get_last_execution_time(name)
        redis { |conn| conn.call('GET', ns("last_execution_time:#{name}")) }
      end

      def set_last_execution_time(name, time)
        redis { |conn| conn.call('SET', ns("last_execution_time:#{name}"), time.to_json) }
      end

      def lock(name)
        redis do |conn|
          id = ns("lock:#{name}")
          conn.call('SET', id, 'true', nx: true, ex: Sidekiq::Grouping::Config.lock_ttl)
        end
      end

      def delete(name)
        redis do |conn|
          conn.call('DEL', ns("last_execution_time:#{name}"))
          conn.call('DEL', ns(name))
          conn.call('SREM', ns('batches'), name)
        end
      end

      private

      def unique_messages_key name
        ns("#{name}:unique_messages")
      end

      def ns(key = nil)
        "batching:#{key}"
      end

      def redis(&block)
        Sidekiq.redis(&block)
      end
    end
  end
end
