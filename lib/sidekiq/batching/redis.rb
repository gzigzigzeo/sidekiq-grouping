module Sidekiq
  module Batching
    class Redis
      def push_msg(name, msg)
        redis do |conn|
          conn.sadd(ns('batches'), name)
          conn.rpush(ns(name), msg)
        end
      end

      def batch_size(name)
        redis { |conn| conn.llen(ns(name)) }
      end

      def batches
        redis { |conn| conn.smembers(ns('batches')) }
      end

      def pluck(name, limit)
        redis do |conn|
          result = conn.pipelined do
            conn.lrange(ns(name), 0, limit - 1)
            conn.lrem(ns(name), 0, limit - 1)
          end

          result.first
        end
      end

      def get_last_execution_time(name)
        redis { |conn| conn.get(ns("last_execution_time:#{name}")) }
      end

      def set_last_execution_time(name, time)
        redis { |conn| conn.set(ns("last_execution_time:#{name}"), time.to_json) }
      end

      def lock(name)
        redis do |conn|
          id = ns("lock:#{name}")
          conn.setnx(id, true).tap do |obtained|
            if obtained
              conn.expire(id, Sidekiq::Batching::Config.lock_ttl)
            end
          end
        end
      end

      private
      def ns(key = nil)
        "batching:#{key}"
      end

      def redis(&block)
        Sidekiq.redis(&block)
      end
    end
  end
end