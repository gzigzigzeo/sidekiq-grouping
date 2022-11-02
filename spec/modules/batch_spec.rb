require 'spec_helper'

describe Sidekiq::Grouping::Batch do
  subject { Sidekiq::Grouping::Batch }

  context 'adding' do
    it 'must enqueue unbatched worker' do
       RegularWorker.perform_async('bar')
       expect(RegularWorker).to have_enqueued_sidekiq_job("bar")
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

    it 'must not enqueue batched worker' do
      ReliableBatchedSizeWorker.perform_async('bar')
      expect_batch(ReliableBatchedSizeWorker, 'reliable_batched_size')
    end

    it 'must not enqueue batched worker' do
      ReliableBatchedUniqueSizeWorker.perform_async('bar')
      expect_batch(ReliableBatchedUniqueSizeWorker, 'reliable_batched_unique_size')
    end

    context 'in bulk' do
      it 'inserts in batches' do
        messages = (0..1005).map(&:to_s)
        mock_redis = Sidekiq::Grouping::Redis.new
        allow(Sidekiq::Grouping::Redis).to receive(:new).and_return(mock_redis)
        expect(mock_redis).to receive(:push_messages).with(anything, messages[0..999], anything).and_call_original
        expect(mock_redis).to receive(:push_messages).with(anything, messages[1000..1005], anything).and_call_original

        BatchedBulkInsertWorker.perform_async(*messages)
        batch = subject.new(BatchedBulkInsertWorker.name, 'batched_bulk_insert')
        expect(batch.size).to eq(1006)
      end
    end
  end

  context 'checking if should flush' do
    it 'must flush if limit exceeds for limit worker' do
      batch = subject.new(BatchedSizeWorker.name, 'batched_size')

      expect(batch.could_flush?).to be_falsy
      BatchedSizeWorker.perform_async('bar')
      expect(batch.could_flush?).to be_falsy
      4.times { BatchedSizeWorker.perform_async('bar') }
      expect(batch.could_flush?).to be_truthy
    end

    it 'must flush if limit exceeds for both worker' do
      batch = subject.new(BatchedBothWorker.name, 'batched_both')

      expect(batch.could_flush?).to be_falsy
      BatchedBothWorker.perform_async('bar')
      expect(batch.could_flush?).to be_falsy
      4.times { BatchedBothWorker.perform_async('bar') }
      expect(batch.could_flush?).to be_truthy
    end

    it 'must flush if limit okay but time came' do
      batch = subject.new(BatchedIntervalWorker.name, 'batched_interval')

      expect(batch.could_flush?).to be_falsy
      BatchedIntervalWorker.perform_async('bar')
      expect(batch.could_flush?).to be_falsy
      expect(batch.size).to eq(1)

      Timecop.travel(2.hours.since)

      expect(batch.could_flush?).to be_truthy
    end
  end

  context 'flushing' do
    it 'must put worker to queue on flush' do
      batch = subject.new(BatchedSizeWorker.name, 'batched_size')

      expect(batch.could_flush?).to be_falsy
      10.times { |n| BatchedSizeWorker.perform_async("bar#{n}") }
      batch.flush
      expect(BatchedSizeWorker).to(
        have_enqueued_sidekiq_job([["bar0"], ["bar1"]])
      )
      expect(batch.size).to eq(7)
    end
  end

  context 'with similar args' do
    context 'option batch_unique = true' do
      it 'enqueues once' do
        batch = subject.new(BatchedUniqueArgsWorker.name, 'batched_unique_args')
        3.times { BatchedUniqueArgsWorker.perform_async('bar', 1) }
        expect(batch.size).to eq(1)
      end

      it 'enqueues once each unique set of args' do
        batch = subject.new(BatchedUniqueArgsWorker.name, 'batched_unique_args')
        3.times { BatchedUniqueArgsWorker.perform_async('bar', 1) }
        6.times { BatchedUniqueArgsWorker.perform_async('baz', 1) }
        3.times { BatchedUniqueArgsWorker.perform_async('bar', 1) }
        2.times { BatchedUniqueArgsWorker.perform_async('baz', 3) }
        7.times { BatchedUniqueArgsWorker.perform_async('bar', 1) }
        expect(batch.size).to eq(3)
      end

      context 'flushing' do

        it 'works' do
          batch = subject.new(BatchedUniqueArgsWorker.name, 'batched_unique_args')
          2.times { BatchedUniqueArgsWorker.perform_async('bar', 1) }
          2.times { BatchedUniqueArgsWorker.perform_async('baz', 1) }
          batch.flush
          expect(batch.size).to eq(0)
        end

        it 'allows to enqueue again after flush' do
          batch = subject.new(BatchedUniqueArgsWorker.name, 'batched_unique_args')
          2.times { BatchedUniqueArgsWorker.perform_async('bar', 1) }
          2.times { BatchedUniqueArgsWorker.perform_async('baz', 1) }
          batch.flush
          BatchedUniqueArgsWorker.perform_async('bar', 1)
          BatchedUniqueArgsWorker.perform_async('baz', 1)
          expect(batch.size).to eq(2)
        end
      end

    end

    context 'batch_unique is not specified' do
      it 'enqueues all' do
        batch = subject.new(BatchedSizeWorker.name, 'batched_size')
        3.times { BatchedSizeWorker.perform_async('bar', 1) }
        expect(batch.size).to eq(3)
      end
    end
  end

  private
  def expect_batch(klass, queue)
    expect(klass).to_not have_enqueued_sidekiq_job("bar")
    batch = subject.new(klass.name, queue)
    stats = subject.all
    expect(batch.size).to eq(1)
    expect(stats.size).to eq(1)
    expect(stats.first.worker_class).to eq(klass.name)
    expect(stats.first.queue).to eq(queue)
    expect(batch.pluck).to eq [['bar']]
  end
end
