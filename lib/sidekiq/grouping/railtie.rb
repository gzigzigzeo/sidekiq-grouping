# frozen_string_literal: true

module Sidekiq
  module Grouping
    class Railtie < ::Rails::Railtie
      config.after_initialize do
        Sidekiq::Grouping.start! if Sidekiq.server?
      end
    end
  end
end
