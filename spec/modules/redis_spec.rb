require 'spec_helper'

describe Sidekiq::Grouping::Redis do
  subject { Sidekiq::Grouping::Redis.new }

  let(:queue_name)    { "my_queue" }
  let(:key)           { "batching:#{queue_name}" }
  let(:unique_key)    { "batching:#{queue_name}:unique_messages" }

  describe "#push_msg" do
    it "adds message to queue" do
      subject.push_msg(queue_name, 'My message')
      expect(redis { |c| c.llen key }).to eq 1
      expect(redis { |c| c.lrange key, 0, 1 }).to eq ['My message']
      expect(redis { |c| c.smembers unique_key}).to eq []
    end

    it "remembers unique message if specified" do
      subject.push_msg(queue_name, 'My message', true)
      expect(redis { |c| c.smembers unique_key}).to eq ['My message']
    end
  end

  describe "#pluck" do
    it "removes messages from queue" do
      subject.push_msg(queue_name, "Message 1")
      subject.push_msg(queue_name, "Message 2")
      subject.pluck(queue_name, 2)
      expect(redis { |c| c.llen key }).to eq 0
    end

    it "forgets unique messages" do
      subject.push_msg(queue_name, "Message 1", true)
      subject.push_msg(queue_name, "Message 2", true)
      expect(redis { |c| c.scard unique_key }).to eq 2
      subject.pluck(queue_name, 2)
      expect(redis { |c| c.smembers unique_key }).to eq []
    end
  end

  private

  def redis(&block)
    Sidekiq.redis(&block)
  end

end
