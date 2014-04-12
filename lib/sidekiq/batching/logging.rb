module Sidekiq
  module Batching
    module Logging
      %w(fatal error warn info debug).each do |level|
        level = level.to_sym

        define_method(level) do |msg|
          Sidekiq::Batching.logger.public_send(level, "[Sidekiq::Batching] #{msg}")
        end
      end
    end
  end
end