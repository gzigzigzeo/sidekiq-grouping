class Sidekiq::Grouping::FlusherObserver
  def update(time, result, ex)
    if ex.is_a?(Concurrent::TimeoutError)
      Sidekiq::Grouping.logger.error(
        "[Sidekiq::Grouping] (#{time}) Execution timed out\n"
      )
    else
      Sidekiq::Grouping.logger.error(
        "[Sidekiq::Grouping] Execution failed with error #{ex}\n"
      )
    end
  end
end
