require 'spec_helper'

describe Sidekiq::Grouping::Redis do
  subject { Sidekiq::Grouping::Redis.new }

  let(:queue_name)    { "my_queue" }
  let(:key)           { "batching:#{queue_name}" }
  let(:unique_key)    { "batching:#{queue_name}:unique_messages" }
  let(:pending_jobs)  { "batching:#{queue_name}:pending_jobs" }

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

  describe "#reliable_pluck" do
    it "removes messages from queue" do
      subject.push_msg(queue_name, "Message 1")
      subject.push_msg(queue_name, "Message 2")
      subject.reliable_pluck(queue_name, 1000)
      expect(redis { |c| c.llen key }).to eq 0
    end

    it "forgets unique messages" do
      subject.push_msg(queue_name, "Message 1", true)
      subject.push_msg(queue_name, "Message 2", true)
      expect(redis { |c| c.scard unique_key }).to eq 2
      subject.reliable_pluck(queue_name, 2)
      expect(redis { |c| c.smembers unique_key }).to eq []
    end

    it "tracks the pending jobs" do
      subject.push_msg(queue_name, "Message 1", true)
      subject.push_msg(queue_name, "Message 2", true)
      subject.reliable_pluck(queue_name, 2)
      expect(redis { |c| c.zcount(pending_jobs, 0, Time.now.utc.to_i) }).to eq 1
      pending_queue_name = redis { |c| c.zscan(pending_jobs, 0)[1][0][0] }
      expect(redis { |c| c.llen(pending_queue_name) }).to eq 2
    end

    it "keeps extra items in the queue" do
      subject.push_msg(queue_name, "Message 1", true)
      subject.push_msg(queue_name, "Message 2", true)
      subject.reliable_pluck(queue_name, 1)
      expect(redis { |c| c.zcount(pending_jobs, 0, Time.now.utc.to_i) }).to eq 1
      pending_queue_name = redis { |c| c.zscan(pending_jobs, 0)[1][0][0] }
      expect(redis { |c| c.llen(pending_queue_name) }).to eq 1
      expect(redis { |c| c.llen key }).to eq 1
    end
  end

  describe "#remove_from_pending" do
    it "removes pending jobs by name" do
      subject.push_msg(queue_name, "Message 1", true)
      subject.push_msg(queue_name, "Message 2", true)
      pending_queue_name, _ = subject.reliable_pluck(queue_name, 2)
      subject.remove_from_pending(queue_name, pending_queue_name)
      expect(redis { |c| c.zcount(pending_jobs, 0, Time.now.utc.to_i) }).to eq 0
    end
  end

  describe "#requeue_expired" do
    it "requeues expired jobs" do
      subject.push_msg(queue_name, "Message 1", false)
      subject.push_msg(queue_name, "Message 2", false)
      pending_queue_name, _ = subject.reliable_pluck(queue_name, 2)
      expect(subject.requeue_expired(queue_name, false, 500).size).to eq 0
      redis { |c| c.zincrby pending_jobs, -1000, pending_queue_name }
      subject.push_msg(queue_name, "Message 2", false)
      expect(subject.requeue_expired(queue_name, false, 500).size).to eq 1
      expect(redis { |c| c.llen key }).to eq 3
      expect(redis { |c| c.lrange(key, 0, -1) }).to match_array(["Message 1", "Message 2", "Message 2"])
    end

    it "removes pending job once enqueued" do
      subject.push_msg(queue_name, "Message 1", true)
      subject.push_msg(queue_name, "Message 2", true)
      pending_queue_name, _ = subject.reliable_pluck(queue_name, 2)
      expect(subject.requeue_expired(queue_name, false, 500).size).to eq 0
      redis { |c| c.zincrby pending_jobs, -1000, pending_queue_name }
      expect(subject.requeue_expired(queue_name, false, 500).size).to eq 1
      expect(redis { |c| c.zcount(pending_jobs, 0, Time.now.utc.to_i) }).to eq 0
    end

    context "with batch_unique == true" do
      it "requeues expired jobs that are not already present" do
        subject.push_msg(queue_name, "Message 1", true)
        subject.push_msg(queue_name, "Message 2", true)
        pending_queue_name, _ = subject.reliable_pluck(queue_name, 2)
        expect(subject.requeue_expired(queue_name, true, 500).size).to eq 0
        redis { |c| c.zincrby pending_jobs, -1000, pending_queue_name }
        subject.push_msg(queue_name, "Message 1", true)
        expect(subject.requeue_expired(queue_name, true, 500).size).to eq 1
        expect(redis { |c| c.llen key }).to eq 2
        expect(redis { |c| c.lrange(key, 0, -1) }).to match_array(["Message 1", "Message 2"])
      end

      it "removes pending job once enqueued" do
        subject.push_msg(queue_name, "Message 1", true)
        subject.push_msg(queue_name, "Message 2", true)
        pending_queue_name, _ = subject.reliable_pluck(queue_name, 2)
        expect(subject.requeue_expired(queue_name, true, 500).size).to eq 0
        redis { |c| c.zincrby pending_jobs, -1000, pending_queue_name }
        subject.push_msg(queue_name, "Message 1", true)
        expect(subject.requeue_expired(queue_name, true, 500).size).to eq 1
        expect(redis { |c| c.zcount(pending_jobs, 0, Time.now.utc.to_i) }).to eq 0
      end
    end
  end

  private

  def redis(&block)
    Sidekiq.redis(&block)
  end

end
