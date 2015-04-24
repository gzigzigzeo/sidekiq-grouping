module Sidekiq
  module Grouping
    module Logging
      %w(fatal error warn info debug).each do |level|
        level = level.to_sym

        define_method(level) do |msg|
          Sidekiq::Grouping.logger.public_send(level, "[Sidekiq::Grouping] #{msg}")
        end
      end
    end
  end
end
