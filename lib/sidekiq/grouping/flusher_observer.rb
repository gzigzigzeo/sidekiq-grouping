# frozen_string_literal: true

module Sidekiq
  module Grouping
    class FlusherObserver
      def update(time, _result, exception)
        if exception.is_a?(Concurrent::TimeoutError)
          Sidekiq::Grouping.logger.error(
            "[Sidekiq::Grouping] (#{time}) Execution timed out\n"
          )
        elsif exception.present?
          Sidekiq::Grouping.logger.error(
            "[Sidekiq::Grouping] Execution failed with error #{exception}\n"
          )
        end
      end
    end
  end
end
