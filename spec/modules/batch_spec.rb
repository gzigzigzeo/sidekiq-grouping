# frozen_string_literal: true

require "spec_helper"

describe Sidekiq::Grouping::Batch do
  subject(:batch_service) { described_class }

  context "when adding" do
    it "must enqueue unbatched worker" do
      RegularWorker.perform_async("bar")
      expect(RegularWorker).to have_enqueued_sidekiq_job("bar")
    end

    it "must not enqueue batched worker based on batch size setting" do
      BatchedSizeWorker.perform_async("bar")
      expect_batch(BatchedSizeWorker, "batched_size")
    end

    it "must not enqueue batched worker based on interval setting" do
      BatchedIntervalWorker.perform_async("bar")
      expect_batch(BatchedIntervalWorker, "batched_interval")
    end

    it "must not enqueue batched worker based on both settings" do
      BatchedBothWorker.perform_async("bar")
      expect_batch(BatchedBothWorker, "batched_both")
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
        expect(mock_redis).to receive(:push_messages).with(anything, messages[0..999].map(&:to_json), anything).and_call_original
        expect(mock_redis).to receive(:push_messages).with(anything, messages[1000..1005].map(&:to_json), anything).and_call_original

        BatchedBulkInsertWorker.perform_async(messages)
        batch = subject.new(BatchedBulkInsertWorker.name, 'batched_bulk_insert')
        expect(batch.size).to eq(1006)
      end

      it 'raises an exception if argument is not an array' do
        failed = false
        begin
          BatchedBulkInsertWorker.perform_async('potato')
        rescue StandardError => e
          failed = true
        end
        expect(failed).to be_truthy
      end

      it 'raises an exception if argument is not a single array' do
        failed = false
        begin
          BatchedBulkInsertWorker.perform_async(['potato'], ['tomato'])
        rescue StandardError => e
          failed = true
        end
        expect(failed).to be_truthy
      end
    end
  end

  context "when checking if should flush" do
    it "must flush if limit exceeds for limit worker", :aggregate_failures do
      batch = batch_service.new(BatchedSizeWorker.name, "batched_size")

      expect(batch).not_to be_could_flush
      BatchedSizeWorker.perform_async("bar")
      expect(batch).not_to be_could_flush
      4.times { BatchedSizeWorker.perform_async("bar") }
      expect(batch).to be_could_flush
    end

    it "must flush if limit exceeds for both worker", :aggregate_failures do
      batch = batch_service.new(BatchedBothWorker.name, "batched_both")

      expect(batch).not_to be_could_flush
      BatchedBothWorker.perform_async("bar")
      expect(batch).not_to be_could_flush
      4.times { BatchedBothWorker.perform_async("bar") }
      expect(batch).to be_could_flush
    end

    it "must flush if limit okay but time came", :aggregate_failures do
      batch = batch_service.new(BatchedIntervalWorker.name, "batched_interval")

      expect(batch).not_to be_could_flush
      BatchedIntervalWorker.perform_async("bar")
      expect(batch).not_to be_could_flush
      expect(batch.size).to eq(1)

      Timecop.travel(2.hours.since)

      expect(batch).to be_could_flush
    end
  end

  context "when flushing" do
    it "must put worker to queue on flush", :aggregate_failures do
      batch = batch_service.new(BatchedSizeWorker.name, "batched_size")

      expect(batch).not_to be_could_flush
      10.times { |n| BatchedSizeWorker.perform_async("bar#{n}") }
      batch.flush
      expect(BatchedSizeWorker).to(
        have_enqueued_sidekiq_job([["bar0"], ["bar1"]])
      )
      expect(batch.size).to eq(7)
    end
  end

  context "with similar args" do
    context "when option batch_unique = true" do
      it "enqueues once" do
        batch = batch_service.new(
          BatchedUniqueArgsWorker.name,
          "batched_unique_args"
        )
        3.times { BatchedUniqueArgsWorker.perform_async("bar", 1) }
        expect(batch.size).to eq(1)
      end

      it "enqueues once each unique set of args" do
        batch = batch_service.new(
          BatchedUniqueArgsWorker.name,
          "batched_unique_args"
        )
        3.times { BatchedUniqueArgsWorker.perform_async("bar", 1) }
        6.times { BatchedUniqueArgsWorker.perform_async("baz", 1) }
        3.times { BatchedUniqueArgsWorker.perform_async("bar", 1) }
        2.times { BatchedUniqueArgsWorker.perform_async("baz", 3) }
        7.times { BatchedUniqueArgsWorker.perform_async("bar", 1) }
        expect(batch.size).to eq(3)
      end

      it "flushes the workers" do
        batch = batch_service.new(
          BatchedUniqueArgsWorker.name,
          "batched_unique_args"
        )
        2.times { BatchedUniqueArgsWorker.perform_async("bar", 1) }
        2.times { BatchedUniqueArgsWorker.perform_async("baz", 1) }
        batch.flush
        expect(batch.size).to eq(0)
      end

      it "allows to enqueue again after flush" do
        batch = batch_service.new(
          BatchedUniqueArgsWorker.name,
          "batched_unique_args"
        )
        2.times { BatchedUniqueArgsWorker.perform_async("bar", 1) }
        2.times { BatchedUniqueArgsWorker.perform_async("baz", 1) }
        batch.flush
        BatchedUniqueArgsWorker.perform_async("bar", 1)
        BatchedUniqueArgsWorker.perform_async("baz", 1)
        expect(batch.size).to eq(2)
      end
    end

    context "when batch_unique is not specified" do
      it "enqueues all" do
        batch = batch_service.new(BatchedSizeWorker.name, "batched_size")
        3.times { BatchedSizeWorker.perform_async("bar", 1) }
        expect(batch.size).to eq(3)
      end
    end
  end

  context "when inline mode" do
    it "must pass args to worker as array" do
      Sidekiq::Testing.inline! do
        expect_any_instance_of(BatchedSizeWorker)
          .to receive(:perform).with([[1]])

        BatchedSizeWorker.perform_async(1)
      end
    end

    it "must not pass args to worker as array" do
      Sidekiq::Testing.inline! do
        expect_any_instance_of(RegularWorker).to receive(:perform).with(1)

        RegularWorker.perform_async(1)
      end
    end
  end

  private

  def expect_batch(klass, queue) # rubocop:disable Metrics/AbcSize
    expect(klass).not_to have_enqueued_sidekiq_job("bar")
    batch = batch_service.new(klass.name, queue)
    stats = batch_service.all
    expect(batch.size).to eq(1)
    expect(stats.size).to eq(1)
    expect(stats.first.worker_class).to eq(klass.name)
    expect(stats.first.queue).to eq(queue)
    expect(batch.pluck).to eq [["bar"]]
  end
end
