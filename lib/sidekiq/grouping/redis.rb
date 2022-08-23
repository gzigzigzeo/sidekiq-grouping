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

      RELIABLE_PLUCK_SCRIPT = <<-LUA
        local queue = KEYS[1]
        local unique_messages = KEYS[2]
        local pending_jobs = KEYS[3]
        local current_time = KEYS[4]
        local this_job = KEYS[5]
        local limit = ARGV[1]

        redis.call('zadd', pending_jobs, current_time, this_job)
        local values = {}
        for i = 1, limit do 
          table.insert(values, redis.call('lmove', queue, this_job, 'left', 'right'))
        end
        redis.call('srem', unique_messages, unpack(values))

        return {this_job, values}
      LUA

      REQUEUE_SCRIPT = <<-LUA
        local expired_queue = KEYS[1]
        local queue = KEYS[2]
        local pending_jobs = KEYS[3]

        local to_requeue = redis.call('llen', expired_queue)
        for i = 1, to_requeue do
          redis.call('lmove', expired_queue, queue, 'left', 'right')
        end
        redis.call('zrem', pending_jobs, expired_queue)
      LUA

      UNIQUE_REQUEUE_SCRIPT = <<-LUA
        local expired_queue = KEYS[1]
        local queue = KEYS[2]
        local pending_jobs = KEYS[3]
        local unique_messages = KEYS[4]

        local to_requeue = redis.call('lrange', expired_queue, 0, -1)
        for i = #to_requeue, 1, -1 do
          local message = to_requeue[i]
          if redis.call('sismember', unique_messages, message) == 0 then
            redis.call('lmove', expired_queue, queue, 'right', 'left')
          end
        end
        redis.call('zrem', pending_jobs, expired_queue)
      LUA

      def initialize
        [PLUCK_SCRIPT, RELIABLE_PLUCK_SCRIPT, REQUEUE_SCRIPT, UNIQUE_REQUEUE_SCRIPT].each do |script|
          redis { |conn| conn.script(:load, script) }
        end
      end

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
        args = [limit]
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

      def requeue_expired(name, unique = false, ttl = 3600)
        redis do |conn|
          conn.zrangebyscore(pending_jobs(name), '0', Time.now.to_i - ttl).each do |expired|
            keys = [expired, ns(name), pending_jobs(name), unique_messages_key(name)]
            args = []
            script = unique ? UNIQUE_REQUEUE_SCRIPT : REQUEUE_SCRIPT
            conn.eval script, keys, args
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
