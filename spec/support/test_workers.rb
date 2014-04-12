class RegularWorker
  include Sidekiq::Worker

  def perform(foo)
  end
end

class BatchedSizeWorker
  include Sidekiq::Worker

  sidekiq_options queue: :batched_size, batch_size: 3

  def perform(foo)
  end
end

class BatchedIntervalWorker
  include Sidekiq::Worker

  sidekiq_options queue: :batched_interval, batch_flush_interval: 3600

  def perform(foo)
  end
end

class BatchedBothWorker
  include Sidekiq::Worker

  sidekiq_options queue: :batched_both, batch_flush_interval: 3600, batch_size: 3

  def perform(foo)
  end
end
