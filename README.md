# Sidekiq::Grouping

<a href="https://evilmartians.com/?utm_source=sidekiq-grouping-gem">
<img src="https://evilmartians.com/badges/sponsored-by-evil-martians.svg" alt="Sponsored by Evil Martians" width="236" height="54">
</a>

Allows to combine similar sidekiq jobs into groups to process them at once.

Useful for:
* Grouping asynchronous API index calls into bulks for bulk updating/indexing.
* Periodical batch updating of recently changing database counters.

## Usage

Create a worker:

```ruby
class ElasticBulkIndexWorker
  include Sidekiq::Worker

  sidekiq_options(
    queue: :group_by_size,
    batch_flush_size: 30,     # Combined jobs will be executed every 30 items enqueued
    batch_flush_interval: 60, # Combined jobs will be executed at least every 60 seconds
    batch_unique: true,       # Prevents jobs with identical arguments to be enqueued
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

## Flush conditions

- If `batch_flush_size` option set - grouping will be performed when batched queue size exceeds this value.
- If `batch_flush_interval` option set - grouping will be performed every given interval.
- If both are set - grouping will be performed when on any condition became true. For example, if `batch_flush_interval` is set to 60 and `batch_flush_size` is set to 5 - group task will be enqueued even just 3 tasks are in the queue at the end of minute.

## Web UI

![Web UI](web.png)

Add this line to your `config/routes.rb` to activate web UI:

```ruby
require "sidekiq/grouping/web"
```

## Configuration

```ruby
Sidekiq::Grouping::Config.poll_interval = 5     # Amount of time between polling batches
Sidekiq::Grouping::Config.max_batch_size = 5000 # Maximum batch size allowed
Sidekiq::Grouping::Config.lock_ttl = 1          # Timeout of lock set when batched job enqueues
```

## TODO

1. Add support redis_pool option.
2. Make able to work together with sidekiq-unique-jobs.

## Installation

Add this line to your application's Gemfile:

    gem 'sidekiq-grouping'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sidekiq-grouping

## Contributing

1. Fork it ( http://github.com/gzigzigzeo/sidekiq-grouping/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
