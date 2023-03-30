# frozen_string_literal: true

class RegularWorker
  include Sidekiq::Worker

  def perform(foo); end
end

class BatchedSizeWorker
  include Sidekiq::Worker

  sidekiq_options queue: :batched_size, batch_flush_size: 3, batch_size: 2

  def perform(foo); end
end

class BatchedIntervalWorker
  include Sidekiq::Worker

  sidekiq_options queue: :batched_interval, batch_flush_interval: 3600

  def perform(foo); end
end

class BatchedBothWorker
  include Sidekiq::Worker

  sidekiq_options(
    queue: :batched_both, batch_flush_interval: 3600, batch_flush_size: 3
  )

  def perform(foo); end
end

class BatchedUniqueArgsWorker
  include Sidekiq::Worker

  sidekiq_options(
    queue: :batched_unique_args, batch_flush_size: 3, batch_unique: true
  )

  def perform(foo); end
end

class ReliableBatchedSizeWorker
  include Sidekiq::Worker

  sidekiq_options(
    queue: :reliable_batched_size, batch_flush_size: 3, batch_size: 2, batch_ttl: 10
  )

  def perform(foo)
  end
end

class ReliableBatchedUniqueSizeWorker
  include Sidekiq::Worker

  sidekiq_options(
    queue: :reliable_batched_unique_size, batch_flush_size: 3, batch_size: 2, batch_ttl: 10, batch_unique: true
  )

  def perform(foo)
  end
end

class BatchedBulkInsertWorker
  include Sidekiq::Worker

  sidekiq_options(
    queue: :batched_bulk_insert, batch_flush_size: 3, batch_size: 2, batch_ttl: 10, batch_merge_array: true
  )

  def perform(foo)
  end
end