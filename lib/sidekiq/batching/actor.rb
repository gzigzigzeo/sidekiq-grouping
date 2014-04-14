module Sidekiq
  module Batching
    class Actor
      include Sidekiq::Batching::Logging
      include Celluloid

      def initialize
        link_to_sidekiq_manager
      end

      private
      def start_polling
        interval = Sidekiq::Batching::Config.poll_interval
        info "Start polling of queue batches every #{interval} seconds"
        every(interval) { flush_batches }
      end

      def flush_batches
        batches = []

        Sidekiq::Batching::Batch.all.map do |batch|
          if batch.could_flush?
            batches << batch
          end
        end

        flush(batches)
      end

      def link_to_sidekiq_manager
        Sidekiq::CLI.instance.launcher.manager.link(current_actor)
        start_polling
      rescue NoMethodError
        debug "Can't link #{self.class.name}. Sidekiq::Manager not running. Retrying in 5 seconds ..."
        after(5) { link_to_sidekiq_manager }
      end

      def flush(batches)
        if batches.any?
          names = batches.map { |batch| "#{batch.worker_class} in #{batch.queue}" }
          info "Trying to flush batched queues: #{names.join(',')}"
          batches.each { |batch| batch.flush }
        end
      end
    end
  end
end