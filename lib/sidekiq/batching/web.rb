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

        app.post "/batching/:name/delete" do
          worker_class, queue = Sidekiq::Batching::Batch.extract_worker_klass_and_queue(params['name'])
          batch = Sidekiq::Batching::Batch.new(worker_class, queue)
          batch.delete
          redirect "#{root_path}/batching"
        end
      end

    end
  end
end

Sidekiq::Web.register(Sidetiq::Batching::Web)
Sidekiq::Web.tabs["Batching"] = "batching"

