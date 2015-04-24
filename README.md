# Sidekiq::Grouping

Lets you batch similar tasks to run them all as a single task.

Allows identical sidekiq jobs to be processed with a single background call.

Useful for:
* Grouping asynchronous API index calls into bulks for bulk updating/indexing.
* Periodical batch updating of recently changing database counters.

Sponsored by [Evil Martians](http://evilmartians.com)

## Usage

Create a worker:

```ruby
class ElasticBulkIndexWorker
  include Sidekiq::Worker

  sidekiq_options(
    queue: :batched_by_size,
    batch_size: 30,           # Jobs will be combined to groups of 30 items
    batch_flush_interval: 60, # Combined jobs will be executed at least every 60 seconds
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

This will happen for every 30 jobs in a row or every 60 seconds.

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
