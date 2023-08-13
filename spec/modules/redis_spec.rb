# frozen_string_literal: true

require "spec_helper"

describe Sidekiq::Grouping::Redis do
  include Sidekiq::Grouping::RedisDispatcher

  subject(:redis_service) { described_class.new }

  let(:queue_name)    { "my_queue" }
  let(:key)           { "batching:#{queue_name}" }
  let(:unique_key)    { "batching:#{queue_name}:unique_messages" }

  describe "#push_msg" do
    it "adds message to queue", :aggregate_failures do
      redis_service.push_msg(queue_name, "My message")
      expect(redis_call(:llen, key)).to eq 1
      expect(redis_call(:lrange, key, 0, 1)).to eq ["My message"]
      expect(redis_call(:smembers, unique_key)).to eq []
    end

    it "remembers unique message if specified" do
      redis_service.push_msg(queue_name, "My message", remember_unique: true)
      expect(redis_call(:smembers, unique_key)).to eq ["My message"]
    end
  end

  describe "#pluck" do
    it "removes messages from queue" do
      redis_service.push_msg(queue_name, "Message 1")
      redis_service.push_msg(queue_name, "Message 2")
      redis_service.pluck(queue_name, 2)
      expect(redis_call(:llen, key)).to eq 0
    end

    it "forgets unique messages", :aggregate_failures do
      redis_service.push_msg(queue_name, "Message 1", remember_unique: true)
      redis_service.push_msg(queue_name, "Message 2", remember_unique: true)
      expect(redis_call(:scard, unique_key)).to eq 2
      redis_service.pluck(queue_name, 2)
      expect(redis_call(:smembers, unique_key)).to eq []
    end
  end

  describe "#pluck_script" do
    context "when Redis version is" do
      it ">= 6.2.0, selects the corresponding pluck script" do
        mock_redis_client = Hashie::Mash.new(
          info: { "redis_version" => "6.2.0" }
        )
        allow_any_instance_of(described_class).to receive(:redis).and_yield(
          mock_redis_client
        )
        expect(redis_service.pluck_script).to eq(
          described_class::PLUCK_SCRIPT_GTE_6_2_0
        )
      end

      it "< 6.2.0, selects the corresponding pluck script" do
        mock_redis_client = Hashie::Mash.new(
          info: { "redis_version" => "6.0.0" }
        )
        allow_any_instance_of(described_class).to receive(:redis).and_yield(
          mock_redis_client
        )
        expect(redis_service.pluck_script).to eq(
          described_class::PLUCK_SCRIPT_LT_6_2_0
        )
      end
    end
  end
end
