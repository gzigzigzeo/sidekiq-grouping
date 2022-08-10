module Sidekiq
  module Grouping
    class Batch
      def initialize(worker_class, queue, redis_pool = nil)
        @worker_class = worker_class
        @queue = queue
        @name = "#{worker_class.underscore}:#{queue}"
        @redis = Sidekiq::Grouping::Redis.new
      end

      attr_reader :name, :worker_class, :queue

      def add(msg)
        msg = msg.to_json
        @redis.push_msg(@name, msg, enqueue_similar_once?) if should_add? msg
      end

      def should_add? msg
        return true unless enqueue_similar_once?
        !@redis.enqueued?(@name, msg)
      end

      def size
        @redis.batch_size(@name)
      end

      def chunk_size
        worker_class_options['batch_size'] ||
          Sidekiq::Grouping::Config.max_batch_size
      end

      def pluck_size
        worker_class_options['batch_flush_size'] ||
          chunk_size
      end

      def pluck
        if @redis.lock(@name)
          @redis.pluck(@name, pluck_size).map { |value| JSON.parse(value) }
        end
      end

      def flush
        return reliable_flush if reliable?

        chunk = pluck
        return unless chunk

        chunk.each_slice(chunk_size) do |subchunk|
          Sidekiq::Client.push(
            'class' => @worker_class,
            'queue' => @queue,
            'args' => [true, subchunk]
          )
        end
        set_current_time_as_last
      end

      def reliable_flush
        pending_name, chunk = reliable_pluck
        return unless chunk

        chunk.each_slice(chunk_size) do |subchunk|
          Sidekiq::Client.push(
            'class' => @worker_class,
            'queue' => @queue,
            'args' => [true, subchunk]
          )
        end
        @redis.remove_from_pending(@name, pending_name)
        set_current_time_as_last
      end

      def reliable_pluck
        if @redis.lock(@name)
          pending_name, items = @redis.reliable_pluck(@name, pluck_size)
          items = items.map { |value| JSON.parse(value) }
          [pending_name, items]
        end
      end

      def worker_class_constant
        @worker_class.constantize
      end

      def worker_class_options
        worker_class_constant.get_sidekiq_options
      rescue NameError
        {}
      end

      def could_flush?
        could_flush_on_overflow? || could_flush_on_time?
      end

      def last_execution_time
        last_time = @redis.get_last_execution_time(@name)
        Time.parse(last_time) if last_time
      end

      def next_execution_time
        if interval = worker_class_options['batch_flush_interval']
          last_time = last_execution_time
          last_time + interval.seconds if last_time
        end
      end

      def delete
        @redis.delete(@name)
      end

      def requeue_expired
        @redis.requeue_expired(@name, reliable_ttl)
      end

      private

      def could_flush_on_overflow?
        size >= pluck_size
      end

      def could_flush_on_time?
        return false if size.zero?

        last_time = last_execution_time
        next_time = next_execution_time

        if last_time.blank?
          set_current_time_as_last
          false
        else
          next_time < Time.now if next_time
        end
      end

      def enqueue_similar_once?
        worker_class_options['batch_unique'] == true
      end

      def reliable?
        worker_class_options['batch_reliable'] == true || Sidekiq::Grouping::Config.reliable == true
      end

      def reliable_ttl
        worker_class_options['batch_reliable_ttl'] || 3600
      end

      def set_current_time_as_last
        @redis.set_last_execution_time(@name, Time.now)
      end

      class << self
        def all
          redis = Sidekiq::Grouping::Redis.new

          redis.batches.map do |name|
            new(*extract_worker_klass_and_queue(name))
          end
        end

        def extract_worker_klass_and_queue(name)
          klass, queue = name.split(':')
          [klass.camelize, queue]
        end
      end
    end
  end
end
