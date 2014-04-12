module Sidekiq
  module Batching
    module Supervisor
      class << self
        include Sidekiq::Batching::Logging

        def run!
          info 'Sidekiq::Batching starts supervision'
          Sidekiq::Batching::Actor.supervise_as(:sidekiq_batching)
        end
      end
    end
  end
end
