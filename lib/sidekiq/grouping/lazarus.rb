class Sidekiq::Grouping::Lazarus
  def revive
    Sidekiq::Grouping::Batch.all.each do |batch|
      batch.requeue_expired
    end
  end
end
