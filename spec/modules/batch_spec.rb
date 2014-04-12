require 'spec_helper'

describe Sidekiq::Batching::Batch do
  subject { Sidekiq::Batching::Batch }

  context 'adding' do
    it 'must enqueue unbatched worker' do
       RegularWorker.perform_async('bar')
       expect(RegularWorker).to have_enqueued_job('bar')
    end

    it 'must not enqueue batched worker' do
      BatchedSizeWorker.perform_async('bar')
      expect_batch(BatchedSizeWorker, 'batched_size')
    end

    it 'must not enqueue batched worker' do
      BatchedIntervalWorker.perform_async('bar')
      expect_batch(BatchedIntervalWorker, 'batched_interval')
    end

    it 'must not enqueue batched worker' do
      BatchedBothWorker.perform_async('bar')
      expect_batch(BatchedBothWorker, 'batched_both')
    end
  end

  context 'checking if should flush' do
    it 'must flush if limit exceeds for limit worker' do
      batch = subject.new(BatchedSizeWorker.name, 'batched_size')

      expect(batch.could_flush?).to be_false
      BatchedSizeWorker.perform_async('bar')
      expect(batch.could_flush?).to be_false
      4.times { BatchedSizeWorker.perform_async('bar') }
      expect(batch.could_flush?).to be_true
    end

    it 'must flush if limit exceeds for both worker' do
      batch = subject.new(BatchedBothWorker.name, 'batched_both')

      expect(batch.could_flush?).to be_false
      BatchedBothWorker.perform_async('bar')
      expect(batch.could_flush?).to be_false
      4.times { BatchedBothWorker.perform_async('bar') }
      expect(batch.could_flush?).to be_true
    end

    it 'must flush if limit okay but time came' do
      batch = subject.new(BatchedIntervalWorker.name, 'batched_both')

      expect(batch.could_flush?).to be_false
      BatchedIntervalWorker.perform_async('bar')
      expect(batch.could_flush?).to be_false

      Timecop.travel(2.hours.since)

      expect(batch.could_flush?).to be_true
    end
  end

  context 'flushing' do
    it 'must put wokrer to queue on flush' do
      batch = subject.new(BatchedSizeWorker.name, 'batched_size')

      expect(batch.could_flush?).to be_false
      10.times { BatchedSizeWorker.perform_async('bar') }
      batch.flush
      expect(BatchedSizeWorker).to have_enqueued_job([["bar"], ["bar"], ["bar"]])
    end
  end

  private
  def expect_batch(klass, queue)
    expect(klass).to_not have_enqueued_job('bar')
    batch = subject.new(klass.name, queue)
    stats = subject.all
    expect(batch.size).to eq(1)
    expect(stats.size).to eq(1)
    expect(stats.first.worker_class).to eq(klass.name)
    expect(stats.first.queue).to eq(queue)
    expect(batch.pluck).to eq [['bar']]
  end
end