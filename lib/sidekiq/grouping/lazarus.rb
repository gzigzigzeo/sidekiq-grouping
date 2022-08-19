class Sidekiq::Grouping::Lazarus
  def revive
    Sidekiq::Grouping::Batch.all.each do |batch|
      next unless batch.is_a?(Sidekiq::Grouping::ReliableBatch)

      batch.requeue_expired
    end
  end
end
