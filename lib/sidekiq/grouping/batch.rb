# frozen_string_literal: true

module Sidekiq
  module Grouping
    class Batch
      def initialize(worker_class, queue, _redis_pool = nil)
        @worker_class = worker_class
        @queue = queue
        @name = "#{worker_class.underscore}:#{queue}"
        @redis = Sidekiq::Grouping::Redis.new
      end

      attr_reader :name, :worker_class, :queue

      def add(msg)
        msg = msg.to_json
        return unless should_add? msg

        @redis.push_msg(
          @name,
          msg,
          remember_unique: enqueue_similar_once?
        )
      end

      def should_add?(msg)
        return true unless enqueue_similar_once?

        !@redis.enqueued?(@name, msg)
      end

      def merge(messages)
        # messages is expected to be an array with a single item which is an array of elements that would normally be added using Sidekiq::Grouping::Batch#add
        raise "batch_merge_array worker received #{messages.size} arguments. Expected a single Array of elements." if messages.size > 1

        messages = messages.first
        raise "batch_merge_array worker received type #{messages.class.name}. Expected Array." unless messages.is_a?(Array)

        messages.each_slice(1000) do |slice|
          @redis.push_messages(@name, slice.map(&:to_json), enqueue_similar_once?)
        end
      end

      def size
        @redis.batch_size(@name)
      end

      def chunk_size
        worker_class_options["batch_size"] ||
          Sidekiq::Grouping::Config.max_batch_size
      end

      def pluck_size
        worker_class_options["batch_flush_size"] ||
          chunk_size
      end

      def pluck
        return unless @redis.lock(@name)

        @redis.pluck(@name, pluck_size).map { |value| JSON.parse(value) }
      end

      def flush
        chunk = pluck
        return unless chunk

        chunk.each_slice(chunk_size) do |subchunk|
          Sidekiq::Client.push(
            "class" => @worker_class,
            "queue" => @queue,
            "args" => [true, subchunk]
          )
        end
        set_current_time_as_last
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
        interval = worker_class_options["batch_flush_interval"]
        return unless interval

        last_time = last_execution_time
        last_time + interval.seconds if last_time
      end

      def delete
        @redis.delete(@name)
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
        elsif next_time
          next_time < Time.now
        end
      end

      def enqueue_similar_once?
        worker_class_options["batch_unique"] == true
      end

      def set_current_time_as_last
        @redis.set_last_execution_time(@name, Time.now)
      end

      class << self
        def all
          redis = Sidekiq::Grouping::Redis.new

          redis.batches.map do |name|
            if Sidekiq::Grouping::Config.reliable
              klass, queue = extract_worker_klass_and_queue(name)
              Sidekiq::Grouping::ReliableBatch.new(klass, queue)
            else
              new(*extract_worker_klass_and_queue(name))
            end
          end
        end

        def extract_worker_klass_and_queue(name)
          klass, queue = name.split(":")
          [klass.camelize, queue]
        end
      end
    end
  end
end
