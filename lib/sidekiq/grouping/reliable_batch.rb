module Sidekiq
  module Grouping
    class ReliableBatch < Batch
      def flush
        pending_name, chunk = pluck
        return unless chunk

        Sidekiq::Client.push_bulk(
          'class' => @worker_class,
          'queue' => @queue,
          'args' => [true, chunk]
        )
        @redis.remove_from_pending(@name, pending_name)
        set_current_time_as_last
      end

      def pluck
        pending_name, items = @redis.reliable_pluck(@name, pluck_size)
        items = items.map { |value| JSON.parse(value) }
        [pending_name, items]
      end

      def requeue_expired
        @redis.requeue_expired(@name, worker_class_options['batch_unique'], reliable_ttl)
      end

      private

      def reliable_ttl
        worker_class_options['batch_reliable_ttl'] || 3600
      end
    end
  end
end
