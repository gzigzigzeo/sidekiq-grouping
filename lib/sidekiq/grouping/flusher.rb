# frozen_string_literal: true

module Sidekiq
  module Grouping
    class Flusher
      def flush
        batches = Sidekiq::Grouping::Batch.all.map do |batch|
          batch if batch.could_flush?
        end
        flush_batches(batches)
      end

      def force_flush_for_test!
        unless Sidekiq::Grouping::Config.tests_env
          Sidekiq::Grouping.logger.warn(
            "**************************************************"
          )
          Sidekiq::Grouping.logger.warn(
            "⛔️ force_flush_for_test! for testing API, " \
            "but this is not the test environment. " \
            "Please check your environment or " \
            "change 'tests_env' to cover this one"
          )
          Sidekiq::Grouping.logger.warn(
            "**************************************************"
          )
        end
        flush_batches(Sidekiq::Grouping::Batch.all)
      end

      private

      def flush_batches(batches)
        batches.compact!
        flush_concrete(batches)
      end

      def flush_concrete(batches)
        return if batches.empty?

        names = batches.map do |batch|
          "#{batch.worker_class} in #{batch.queue}"
        end
        unless Sidekiq::Grouping::Config.tests_env
          Sidekiq::Grouping.logger.info(
            "[Sidekiq::Grouping] Trying to flush batched queues: " \
            "#{names.join(',')}"
          )
        end
        batches.each(&:flush)
      end
    end
  end
end
