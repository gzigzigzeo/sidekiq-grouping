$LOAD_PATH << "." unless $LOAD_PATH.include?(".")

require "rubygems"
require "bundler/setup"
require "timecop"
require "simplecov"
require "sidekiq"
require "rspec-sidekiq"
require "support/test_workers"

SimpleCov.start do
  add_filter "spec"
end

require "sidekiq/grouping"

Sidekiq::Grouping.logger = nil
Sidekiq.configure_client do |config|
  config.redis = { db: 1 }
  config.logger = nil
end

RSpec::Sidekiq.configure do |config|
  config.clear_all_enqueued_jobs = true
  config.warn_when_jobs_not_processed_by_sidekiq = false
end

RSpec.configure do |config|
  config.order = :random
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  config.before :each do
    Sidekiq.redis do |conn|
      keys = conn.call('KEYS', "*batching*")
      keys.each { |key| conn.call('DEL', key) }
    end
  end

  config.after :each do
    Timecop.return
  end
end

$LOAD_PATH << File.join(File.dirname(__FILE__), "..", "lib")
