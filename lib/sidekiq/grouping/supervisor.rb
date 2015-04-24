module Sidekiq
  module Grouping
    module Supervisor
      class << self
        include Sidekiq::Grouping::Logging

        def run!
          info 'Sidekiq::Grouping starts supervision'
          Sidekiq::Grouping::Actor.supervise_as(:sidekiq_grouping)
        end
      end
    end
  end
end
