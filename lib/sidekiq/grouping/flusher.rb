class Sidekiq::Grouping::Fluser
  def flush
    batches = Sidekiq::Grouping::Batch.all.map do |batch|
      batch if batch.could_flush?
    end
    batches.compact!
    flush_concrete(batches)
  end

  private

  def flush_concrete(batches)
    return if batches.empty?
    names = batches.map { |batch| "#{batch.worker_class} in #{batch.queue}" }
    Sidekiq::Grouping.logger.info(
      "[Sidekiq::Grouping] Trying to flush batched queues: #{names.join(',')}"
    )
    batches.each(&:flush)
  end

  class << self
    def start!
      interval = Sidekiq::Grouping::Config.poll_interval
      task = Concurrent::TimerTask.new(
        execution_interval: interval
      ) { new.flush }
      task.add_observer(Sidekiq::Grouping::FlusherObserver.new)
      Sidekiq::Grouping.logger.info(
        "[Sidekiq::Grouping] Started polling batches every #{interval} seconds"
      )
    end
  end
end
