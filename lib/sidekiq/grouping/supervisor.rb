module Sidekiq
  module Grouping
    module Supervisor
      class << self
        include Sidekiq::Grouping::Logging

        if Celluloid::VERSION >= '0.17'
        def run!
          info 'Sidekiq::Grouping starts supervision'
          Sidekiq::Grouping::Actor.supervise as: :sidekiq_grouping
        end
        else
        def run!
          info 'Sidekiq::Grouping starts supervision'
          Sidekiq::Grouping::Actor.supervise_as(:sidekiq_grouping)
        end
        end
      end
    end
  end
end
