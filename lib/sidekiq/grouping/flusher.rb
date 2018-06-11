class Sidekiq::Grouping::Flusher
  def flush
    batches = Sidekiq::Grouping::Batch.all.map do |batch|
      batch if batch.could_flush?
    end
    batches.compact!
    flush_concrete(batches)
  end

  def force_flush_for_test!
    if defined?(::Rails) && Rails.respond_to?(:env) && !Rails.env.test?
      puts("**************************************************")
      puts("⛔️ WARNING: force_flush_for_test! for testing API, but this is not the test environment.")
      puts("**************************************************")
    end
    batches = Sidekiq::Grouping::Batch.all
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
end
