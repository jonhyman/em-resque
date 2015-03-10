$LOAD_PATH.unshift 'lib'
require 'em-resque/version'

Gem::Specification.new do |s|
  s.name              = "em-resque"
  s.version           = EventMachine::Resque::Version
  s.date              = Time.now.strftime('%Y-%m-%d')
  s.summary           = "Em-resque is an async non-forking version of Resque"
  s.homepage          = "http://github.com/SponsorPay/em-resque"
  s.email             = "julius.bruijn@sponsorpay.com"
  s.authors           = [ "Julius de Bruijn" ]

  s.files             = %w( README.markdown Rakefile LICENSE HISTORY.md )
  s.files            += Dir.glob("lib/**/*")
  s.files            += Dir.glob("man/**/*")
  s.files            += Dir.glob("test/**/*")
  s.files            += Dir.glob("tasks/**/*")

  s.extra_rdoc_files  = [ "LICENSE", "README.markdown" ]
  s.rdoc_options      = ["--charset=UTF-8"]

  s.add_dependency "resque", "~> 1.2"
  s.add_dependency "em-synchrony", "~> 1.0.0"

  s.description = <<description
    Em-resque is a version of Resque, which offers non-blocking and non-forking
    workers. The idea is to have fast as possible workers for tasks with lots of
    IO like pinging third party servers or hitting the database.

    The async worker is using fibers through Synchrony library to reduce the amount
    of callback functions. There's one fiber for worker and if one of the workers
    is blocking, it will block all the workers at the same time.

    The idea to use this version and not the regular Resque is to reduce the amount
    of SQL connections for high-load services. Using one process for many workers
    gives a better control to the amount of SQL connections.

    For using Resque please refer the original project.

    https://github.com/defunkt/resque/

    The library adds two rake tasks over Resque:

      * resque:work_async for working inside the EventMachine
description
end
