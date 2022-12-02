# frozen_string_literal: true

module Sidekiq
  module Grouping
    class Middleware
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def call(worker_class, msg, queue, redis_pool = nil)
        if worker_class.is_a?(String)
          worker_class = worker_class.camelize.constantize
        end
        options = worker_class.get_sidekiq_options

        batch =
          options.key?("batch_flush_size") ||
          options.key?("batch_flush_interval") ||
          options.key?("batch_size")

        passthrough =
          msg["args"].is_a?(Array) &&
          msg["args"].try(:first) == true

        retrying = msg["failed_at"].present?

        return yield unless batch

        if inline_mode?
          wrapped_args = [[msg["args"]]]
          msg["args"] = wrapped_args
          return yield
        end

        if passthrough || retrying
          msg["args"].shift if passthrough
          yield
        else
          add_to_batch(worker_class, queue, msg, redis_pool)
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      private

      def add_to_batch(worker_class, queue, msg, redis_pool = nil)
        Sidekiq::Grouping::Batch
          .new(worker_class.name, queue, redis_pool)
          .add(msg["args"])

        nil
      end

      def inline_mode?
        defined?(Sidekiq::Testing) && Sidekiq::Testing.inline?
      end
    end
  end
end
