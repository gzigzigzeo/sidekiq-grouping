module Sidekiq
  module Grouping
    class Redis

      PLUCK_SCRIPT = <<-SCRIPT
        local pluck_values = redis.call('lrange', KEYS[1], 0, ARGV[1] - 1)
        redis.call('ltrim', KEYS[1], ARGV[1], -1)
        for k, v in pairs(pluck_values) do
          redis.call('srem', KEYS[2], v)
        end
        return pluck_values
      SCRIPT

      # keys: 1 = queue, 2 = unique message, 3 = pending jobs, 4 = current time, 5 = this job
      RELIABLE_PLUCK_SCRIPT = <<-SCRIPT
        redis.call('zadd', KEYS[3], KEYS[4], KEYS[5])
        redis.call('renamenx', KEYS[1], KEYS[5])
        local leftovers = redis.call('lrange', KEYS[5], ARGV[1], -1)
        for i = #leftovers, 1, -1 do 
          redis.call('lmove', KEYS[5], KEYS[1], 'right', 'left')
        end

        local pluck_values = redis.call('lrange', KEYS[5], 0, -1)
        for k, v in pairs(pluck_values) do
          redis.call('srem', KEYS[2], v)
        end
        return {KEYS[5], pluck_values}
      SCRIPT

      REQUEUE_SCRIPT = <<~SCRIPT
        local to_requeue = redis.call('lrange', KEYS[1], 0, -1)
        for i = #to_requeue, 1, -1 do 
          redis.call('lpush', KEYS[2], to_requeue[i])
        end
      SCRIPT

      def push_msg(name, msg, remember_unique = false)
        redis do |conn|
          conn.multi do |pipeline|
            pipeline.sadd(ns("batches"), name)
            pipeline.rpush(ns(name), msg)
            pipeline.sadd(unique_messages_key(name), msg) if remember_unique
          end
        end
      end

      def enqueued?(name, msg)
        redis do |conn|
          conn.sismember(unique_messages_key(name), msg)
        end
      end

      def batch_size(name)
        redis { |conn| conn.llen(ns(name)) }
      end

      def batches
        redis { |conn| conn.smembers(ns("batches")) }
      end

      def pluck(name, limit)
        keys = [ns(name), unique_messages_key(name)]
        args = [limit]
        redis { |conn| conn.eval PLUCK_SCRIPT, keys, args }
      end

      def reliable_pluck(name, limit)
        keys = [ns(name), unique_messages_key(name), pending_jobs(name), Time.now.to_i, this_job_name(name)]
        args = [limit, 7.days]
        redis { |conn| conn.eval RELIABLE_PLUCK_SCRIPT, keys, args }
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
          conn.set(id, true, nx: true, ex: Sidekiq::Grouping::Config.lock_ttl)
        end
      end

      def delete(name)
        redis do |conn|
          conn.del(ns("last_execution_time:#{name}"))
          conn.del(ns(name))
          conn.srem(ns('batches'), name)
        end
      end

      def remove_from_pending(name, batch_name)
        redis { |conn| conn.zrem(pending_jobs(name), batch_name) }
      end

      def requeue_expired(name, ttl=3600)
        redis do |conn|
          conn.zrangebyscore(pending_jobs(name), '0', Time.now.to_i - ttl).each do |expired|
            keys = [expired, ns(name)]
            args = []
            conn.eval REQUEUE_SCRIPT, keys, args
            remove_from_pending(name, expired)
          end
        end
      end

      private

      def unique_messages_key name
        ns("#{name}:unique_messages")
      end

      def pending_jobs name
        ns("#{name}:pending_jobs")
      end

      def this_job_name name
        ns("#{name}:#{SecureRandom.hex}")
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
