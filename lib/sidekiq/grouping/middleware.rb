module Sidekiq
  module Grouping
    class Middleware
      # just a proof of concept - ideally should be stored in config
      GROUPED_QUEUE = "metrics".freeze

      def call(worker_class, msg, queue, redis_pool = nil)
        return yield if (defined?(Sidekiq::Testing) && Sidekiq::Testing.inline?)

        passthrough =
          msg['args'] &&
          msg['args'].is_a?(Array) &&
          msg['args'].try(:first) == true

        retrying = msg["failed_at"].present?

        return yield unless batch?(queue)

        if !(passthrough || retrying)
          add_to_batch(worker_class, queue, msg, redis_pool)
        else
          msg['args'].shift if passthrough
          yield
        end
      end

      private

      def batch?(queue)
        queue == GROUPED_QUEUE
      end

      def add_to_batch(worker_class, queue, msg, redis_pool = nil)
        Sidekiq::Grouping::Batch.new(worker_class, queue, redis_pool)
          .add(msg['args'])

        nil
      end
    end
  end
end
