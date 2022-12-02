# frozen_string_literal: true

$LOAD_PATH << "." unless $LOAD_PATH.include?(".")

require "rubygems"
require "bundler/setup"
require "timecop"
require "simplecov"
require "sidekiq"
require "rspec-sidekiq"
require "support/test_workers"
require "pry"

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

  config.before do
    Sidekiq.redis do |conn|
      if Sidekiq::VERSION[0].to_i >= 7
        keys = conn.call("KEYS", "*batching*")
        keys.each { |key| conn.call("DEL", key) }
      else
        keys = conn.keys "*batching*"
        keys.each { |key| conn.del key }
      end
    end
  end

  config.after do
    Timecop.return
  end
end

$LOAD_PATH << File.join(File.dirname(__FILE__), "..", "lib")
