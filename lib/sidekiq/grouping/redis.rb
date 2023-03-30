# frozen_string_literal: true

require_relative "./redis_dispatcher"

module Sidekiq
  module Grouping
    class Redis
      include RedisDispatcher

      PLUCK_SCRIPT = <<-SCRIPT
        local pluck_values = redis.call('lpop', KEYS[1], ARGV[1]) or {}
        if #pluck_values > 0 then
          redis.call('srem', KEYS[2], unpack(pluck_values))
        end
        return pluck_values
      SCRIPT

      RELIABLE_PLUCK_SCRIPT = <<-LUA
        local queue = KEYS[1]
        local unique_messages = KEYS[2]
        local pending_jobs = KEYS[3]
        local current_time = KEYS[4]
        local this_job = KEYS[5]
        local limit = tonumber(ARGV[1])

        redis.call('zadd', pending_jobs, current_time, this_job)
        local values = {}
        for i = 1, math.min(limit, redis.call('llen', queue)) do
          table.insert(values, redis.call('lmove', queue, this_job, 'left', 'right'))
        end
        if #values > 0 then
          redis.call('srem', unique_messages, unpack(values))
        end

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
        for i = 1, #to_requeue do
          local message = to_requeue[i]
          if redis.call('sismember', unique_messages, message) == 0 then
            redis.call('lmove', expired_queue, queue, 'left', 'right')
          else
            redis.call('lpop', expired_queue)
          end
        end
        redis.call('zrem', pending_jobs, expired_queue)
      LUA

      MERGE_ARRAY_SCRIPT = <<-LUA
        local batches = KEYS[1]
        local name = KEYS[2]
        local namespaced_name = KEYS[3]
        local unique_messages_key = KEYS[4]
        local remember_unique = KEYS[5]
        local messages = ARGV

        if remember_unique == 'true' then
          local existing_messages = redis.call('smismember', unique_messages_key, unpack(messages))
          local result = {}
          
          for index, value in ipairs(messages) do
            if existing_messages[index] == 0 then
              result[#result + 1] = value
            end
          end
          
          messages = result
        end

        redis.call('sadd', batches, name)
        redis.call('rpush', namespaced_name, unpack(messages))
        if remember_unique == 'true' then
          redis.call('sadd', unique_messages_key, unpack(messages))
        end
      LUA


      def initialize
        scripts = {
          pluck: PLUCK_SCRIPT,
          reliable_pluck: RELIABLE_PLUCK_SCRIPT,
          requeue: REQUEUE_SCRIPT,
          unique_requeue: UNIQUE_REQUEUE_SCRIPT,
          merge_array: MERGE_ARRAY_SCRIPT
        }

        @script_hashes = {
          pluck: nil,
          reliable_pluck: nil,
          requeue: nil,
          unique_requeue: nil,
          merge_array: nil
        }

        scripts.each_pair do |key, value|
          @script_hashes[key] = redis { |conn| conn.script(:load, value) }
        end
      end

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

      def push_messages(name, messages, remember_unique = false)
        keys = [ns('batches'), name, ns(name), unique_messages_key(name), remember_unique]
        args = [messages]
        redis { |conn| conn.evalsha @script_hashes[:merge_array], keys, args }
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
            :evalsha,
            @script_hashes[:pluck],
            2,
            ns(name),
            unique_messages_key(name),
            limit
          )
        else
          keys = [ns(name), unique_messages_key(name)]
          args = [limit]
          redis_call(:evalsha, @script_hashes[:pluck], keys, args)
        end
      end

      def reliable_pluck(name, limit)
        keys = [ns(name), unique_messages_key(name), pending_jobs(name), Time.now.to_i, this_job_name(name)]
        args = [limit]
        redis { |conn| conn.evalsha @script_hashes[:reliable_pluck], keys, args }
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

      def remove_from_pending(name, batch_name)
        redis do |conn|
          conn.multi do |pipeline|
            pipeline.del(batch_name)
            pipeline.zrem(pending_jobs(name), batch_name)
          end
        end
      end

      def requeue_expired(name, unique = false, ttl = 3600)
        redis do |conn|
          conn.zrangebyscore(pending_jobs(name), '0', Time.now.to_i - ttl).each do |expired|
            keys = [expired, ns(name), pending_jobs(name), unique_messages_key(name)]
            args = []
            script = unique ? @script_hashes[:unique_requeue] : @script_hashes[:requeue]
            conn.evalsha script, keys, args
          end
        end
      end

      private

      def unique_messages_key(name)
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
    end
  end
end
