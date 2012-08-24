EM::Resque
==========

EM::Resque is an addition to [Resque][0] for asynchronic processing of the
background jobs created by Resque. It works like the original Resque worker,
but runs inside an [EventMachine][1] and uses the same process instead of
forking a new one for every job. It can run N workers inside one process, it
packs all of them in Ruby fibers. The library is meant for small but IO-heavy
jobs, which won't use much of CPU power in the running server.

Read the blog post [Resque with EventMachine][4] about solving our problems with this gem.

Use cases
---------

EM::Resque is good for processing background jobs which are doing lots of IO.
The evented nature of the reactor core is great when accessing third
party services with HTTP or doing lots of database-intensive work. When
combined with a connection pool to a SQL server it lets you easily control the
amount of connections, being at the same time extremely scalable.

Overview
--------

EM::Resque jobs are created and queued like with the synchronous version. When
queued, one of the workers in the fiber pool will pick it up and process
the job.

When making IO actions inside a job, it should never block the other workers. E.g.
database operations etc. should be handled with libraries that support EventMachine
to allow concurrent processing.

Resque jobs are Ruby classes (or modules) which respond to the
`perform` method. Here's an example:

``` ruby
class Pinger
  @queue = :ping_publisher

  def self.perform(url)
    res = Result.new
    res.http_result = EventMachine::HttpRequest.new(url).get.response
    res.save
  end
end
```

The `@queue` class instance variable determines which queue `Pinger`
jobs will be placed in. Queues are arbitrary and created on the fly -
you can name them whatever you want and have as many as you want.

To place an `Pinger` job on the `ping_publisher` queue, we might add this
to our application's pre-existing `Callback` class:

``` ruby
class Callback
  def async_ping_publisher
    Resque.enqueue(Pinger, self.callback_url)
  end
end
```

Now when we call `callback.async_ping_publisher` in our
application, a job will be created and placed on the `ping_publisher`
queue.

For more use cases please refer [the original Resque manual][0].

Let's start 100 async workers to work on `ping_publisher` jobs:

    $ cd app_root
    $ QUEUE=file_serve FIBERS=100 rake em_resque:work

This starts the EM::Resque process and loads 100 fibers with a worker inside
each fiber and tells them to work off the `ping_publisher` queue. As soon as
one of the workers is doing it's first IO action it will go to a "yield" mode
to get data back from the IO and allow another one to start a new job. The
event loop resumes the worker when it has some data back from the IO action.

The workers also reserve the jobs for them so the other workers won't touch them.

Workers can be given multiple queues (a "queue list") and run on
multiple machines. In fact they can be run anywhere with network
access to the Redis server.

Jobs
----

What should you run in the background with EM::Resque? Anything with lots of
IO and which takes any time at all. Best use case is gathering data and sending
pings to 3rd party services, which might or might not answer in a decent time.

At SponsorPay we use EM::Resque to process the following types of jobs:

* Simple messaging between our frontend and backend softwares
* Pinging publishers and affiliate networks 

We're handling a tremendious amount of traffic with a bit over 100 workers,
using a lot less of database connections, memory and cpu power compared to the
synchronous and forking Resque or Delayed Job.

All the environment options from the original Resque work also in EM::Resque.
There are also couple of more variables.

### The amount of fibers

The number of fibers for the current process is set in FIBERS variable. One
fiber equals one worker. They are all polling the same queue and terminated
when the main process terminates. The default value is 1.

    $ QUEUE=ping_publisher FIBERS=50 rake em_resque:work

### Signals

EM:Resque workers respond to a few different signals:

* `QUIT` / `TERM` / `INT` - Wait for workers to finish processing then exit

The Front End
-------------

EM::Resque uses the same frontend as Resque. 

EM::Resque Dependencies
-----------------------

    $ gem install bundler
    $ bundle install

Installing EM::Resque
---------------------

### In a Rack app, as a gem

First install the gem.

    $ gem install em-resque

Next include it in your application.

``` ruby
require 'em-resque'
```

Now start your application:

    rackup config.ru

That's it! You can now create EM::Resque jobs from within your app.

To start a worker, create a Rakefile in your app's root (or add this
to an existing Rakefile):

``` ruby
require 'your/app'
require 'em-resque/tasks'
```

Now:

    $ QUEUE=* FIBERS=50 rake em_resque:work

Alternately you can define a `resque:setup` hook in your Rakefile if you
don't want to load your app every time rake runs.

### In a Rails 3 app, as a gem

*EM::Resque is not supporting Rails with Rake at the moment. Needs more work.*

To run EM::Resque with your Rails application, you need a specified script to
load all the needed libraries and start the workers.

*script/resque_async.rb*

``` ruby
RAILS_ENV = ENV['RAILS_ENV'] || 'development_async'
RAILS_ROOT = Dir.pwd

require 'rubygems'
require 'yaml'
require 'uri'
require 'em-resque'
require 'em-resque/worker_machine'
require 'em-resque/task_helper'
require 'resque-retry'
require 'em-synchrony'
require 'em-synchrony/connection_pool'
require 'em-synchrony/mysql2'

Dir.glob(File.join(RAILS_ROOT, 'lib', 'async_worker', '**', '*.rb')).sort.each{|f| require File.expand_path(f)}

resque_config = YAML.load_file("#{RAILS_ROOT}/config/resque.yml")
proxy_config = YAML.load_file("#{RAILS_ROOT}/config/proxy.yml")
PROXY = proxy_config ? proxy_config[RAILS_ENV] : nil

opts = TaskHelper.parse_opts_from_env.merge(:redis => resque_config[RAILS_ENV])
EM::Resque::WorkerMachine.new(opts).start
```

You can start the script with the same environment variables as with the Rake
task.

Now we have our own minimal ORM backed with em-powered mysql connection pool to
handle our models, but there's a library in [em-synchrony][2] called
em-activerecord which can be combined with [async mysql2][3] library to handle
sql connections inside the EventMachine. 

Configuration
-------------

You may want to change the Redis host and port Resque connects to, or
set various other options at startup.

WorkerMachine has a `redis` parameter in the initializer, which can be 
given a string or a Redis object. This means if you're already using 
Redis in your app, EM::Resquec an re-use the existing connection. 
EM::Resque is using the non-blocking em-redis when given the host as a
string. If using a Redis object, please use the non-blocking
EM::Hiredis.

String: `EM::Resque::WorkerMachine.new(opts.merge(:redis => 'localhost:6379'))`

Redis: `EM::Resque::WorkerMachine.new(opts.merge(:redis => $redis))`

Namespaces
----------

If you're running multiple, separate instances of Resque you may want
to namespace the keyspaces so they do not overlap. This is not unlike
the approach taken by many memcached clients.

This feature is provided by the [redis-namespace][rs] library, which
Resque uses by default to separate the keys it manages from other keys
in your Redis server.

Simply use the `EM::Resque.redis.namespace` accessor:

``` ruby
EM::Resque.redis.namespace = "resque:SponsorPay"
```

We recommend sticking this in your initializer somewhere after Redis
is configured.

Contributing
------------

1. Fork EM::Resque
2. Create a topic branch - `git checkout -b my_branch`
3. Push to your branch - `git push origin my_branch`
4. Create a [Pull Request](http://help.github.com/pull-requests/) from your branch
5. That's it!

Meta
----

* Code: `git clone git://github.com/SponsorPay/em-resque.git`
* Home: <http://github.com/SponsorPay/em-resque>
* Bugs: <http://github.com/SponsorPay/em-resque/issues>
* Gems: <http://gemcutter.org/gems/em-resque>

Author
------

Julius de Bruijn :: julius.bruijn@sponsorpay.com :: @pimeys

[0]: http://github.com/defunkt/resque
[1]: http://rubyeventmachine.com/
[2]: https://github.com/igrigorik/em-synchrony
[3]: https://github.com/brianmario/mysql2/blob/master/lib/mysql2/em.rb
[4]: http://sponsorpay.github.com/blog/2012/01/03/resque-with-eventmachine/
