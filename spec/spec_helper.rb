$LOAD_PATH << "." unless $LOAD_PATH.include?(".")

require 'rubygems'
require 'bundler/setup'
require 'timecop'
require 'simplecov'
require 'celluloid/autostart'
require 'sidekiq'
require 'rspec-sidekiq'
require 'support/test_workers'

SimpleCov.start do
  add_filter 'spec'
end

require 'sidekiq/grouping'

Sidekiq::Grouping.logger = nil
Sidekiq.redis = { namespace: ENV['namespace'] }
Sidekiq.logger = nil

RSpec::Sidekiq.configure do |config|
  config.clear_all_enqueued_jobs = true
end

RSpec.configure do |config|
  config.order = :random
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  config.before :each do
    Sidekiq.redis do |conn|
      keys = conn.keys '*batching*'
      keys.each { |key| conn.del key }
    end
  end

  config.after :each do
    Timecop.return
  end
end

$: << File.join(File.dirname(__FILE__), '..', 'lib')
