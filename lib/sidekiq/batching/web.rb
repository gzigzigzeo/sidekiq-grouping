require 'sidekiq/web'

module Sidetiq
  module Batching
    module Web
      VIEWS = File.expand_path('views', File.dirname(__FILE__))

      def self.registered(app)
        app.get "/batching" do
          @batches = Sidekiq::Batching::Batch.all
          erb File.read(File.join(VIEWS, 'index.erb')), locals: {view_path: VIEWS}
        end
      end
    end
  end
end

Sidekiq::Web.register(Sidetiq::Batching::Web)
Sidekiq::Web.tabs["Batching"] = "batching"

