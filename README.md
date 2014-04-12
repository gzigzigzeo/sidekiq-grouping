# Sidekiq::Batching

Allows identical sidekiq jobs to be processed with a single background call.

Useful for:
* Grouping asynchronous API index calls into bulks for bulk updating/indexing.
* Periodical batch updating of recently changing database counters.

## Usage

Create a worker:

```ruby
class ElasticBulkIndexWorker
  include Sidekiq::Worker

  sidekiq_options(
    queue: :batched_by_size,
    batch_size: 30,
    batch_flush_interval: 30,
    retry: 5
  )

  def perform(group)
    client = Elasticsearch::Client.new
    client.bulk(body: group.flatten)
  end
end
```

Perform a jobs:

```ruby
ElasticBulkIndexWorker.perform_async({ delete: { _index: 'test', _id: 5, _type: 'user' } })
ElasticBulkIndexWorker.perform_async({ delete: { _index: 'test', _id: 6, _type: 'user' } })
ElasticBulkIndexWorker.perform_async({ delete: { _index: 'test', _id: 7, _type: 'user' } })
...
```

This jobs will be grouped into a single job which will be performed with the single argument containing:

```ruby
[
  [{ delete: { _index: 'test', _id: 5, _type: 'user' } }],
  [{ delete: { _index: 'test', _id: 6, _type: 'user' } }],
  [{ delete: { _index: 'test', _id: 7, _type: 'user' } }]
  ...
]
```

This will happen for every 30 jobs in a row or every 30 seconds.

Add this line to your `config/routes.rb` to activate web UI:

```ruby
require "sidekiq/batching/web"
```

## Configuration

```ruby
Sidekiq::Batching::Config.poll_interval = 5     # Amount of time between polling batches
Sidekiq::Batching::Config.max_batch_size = 5000 # Maximum batch size allowed
Sidekiq::Batching::Config.lock_ttl = 1          # Timeout of lock set when batched job enqueues
```

## Notes

1. Did not tested with sidekiq 3.
1. Does not support sidekiq 3 redis_pool option.

## Installation

Add this line to your application's Gemfile:

    gem 'sidekiq-batching'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sidekiq-batching

## Contributing

1. Fork it ( http://github.com/gzigzigzeo/sidekiq-batching/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
