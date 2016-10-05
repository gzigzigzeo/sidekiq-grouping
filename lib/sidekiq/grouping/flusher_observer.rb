class Sidekiq::Grouping::FlusherObserver
  def update(time, _result, ex)
    if ex.is_a?(Concurrent::TimeoutError)
      Sidekiq::Grouping.logger.error(
        "[Sidekiq::Grouping] (#{time}) Execution timed out\n"
      )
    elsif ex.present?
      Sidekiq::Grouping.logger.error(
        "[Sidekiq::Grouping] Execution failed with error #{ex}\n"
      )
    end
  end
end
