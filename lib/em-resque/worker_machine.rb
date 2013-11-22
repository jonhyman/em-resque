require 'em-synchrony'
require 'em-resque'
require 'em-resque/worker'

module EventMachine
  module Resque
    # WorkerMachine is an EventMachine with Resque workers wrapped in Ruby
    # fibers.
    #
    # An instance contains the workers and a system monitor running inside an
    # EventMachine. The monitoring takes care of stopping the machine when all
    # workers are shut down.

    class WorkerMachine
      # Initializes the machine, creates the fibers and workers, traps quit
      # signals and prunes dead workers
      #
      # == Options
      # fibers::       The number of fibers to use in the worker (default 1)
      # interval::     Time in seconds how often the workers check for new work
      #                (default 5)
      # queues::       Which queues to poll (default all)
      # verbose::      Verbose log output (default false)
      # vverbose::     Even more verbose log output (default false)
      # pidfile::      The file to save the process id number
      # tick_instead_of_sleep::      Whether to tick through the reactor polling for jobs or use EM::Synchrony.sleep.
      #                              Note that if you use this option, you'll be limited to 1 fiber.
      def initialize(opts = {})
        @interval = opts[:interval] || 5
        @fibers_count = opts[:fibers] || 1
        @queues = opts[:queue] || opts[:queues] || '*'
        @verbose = opts[:logging] || opts[:verbose] || false
        @very_verbose = opts[:vverbose] || false
        @pidfile = opts[:pidfile]
        @redis_namespace = opts[:namespace] || :resque
        @redis_uri = opts[:redis] || "redis://127.0.0.1:6379"
        @tick_instead_of_sleep = !opts[:tick_instead_of_sleep].nil? ? opts[:tick_instead_of_sleep] : false

        # If we're ticking instead of sleeping, we can only have one fiber
        if @tick_instead_of_sleep
          @fibers_count = 1
        end

        raise(ArgumentError, "Should have at least one fiber") if @fibers_count.to_i < 1

        build_workers
        build_fibers
        create_pidfile
      end

      # Start the machine and start polling queues.
      def start
        EM.epoll
        EM.synchrony do
          EM::Resque.initialize_redis(@redis_uri, @redis_namespace, @fibers_count)
          trap_signals
          prune_dead_workers
          @fibers.each(&:resume)

          # If we're ticking and not sleeping, we don't need to monitor for yielding
          unless @tick_instead_of_sleep
            system_monitor.resume
          end
        end
      end

      # Stop the machine.
      def stop
        @workers.each(&:shutdown)
      end

      def fibers
        @fibers || []
      end

      def workers
        @workers || []
      end

      private

      # Builds the workers to poll the given queues.
      def build_workers
        queues = @queues.to_s.split(',')

        @workers = (1..@fibers_count.to_i).map do
          worker = EM::Resque::Worker.new(*queues)
          worker.verbose = @verbose
          worker.very_verbose = @very_verbose
          worker.tick_instead_of_sleep = @tick_instead_of_sleep

          worker
        end
      end

      # Builds the fibers to contain the built workers.
      def build_fibers
        @fibers = @workers.map do |worker|
          Fiber.new do
            worker.log "starting async worker #{worker}"
            worker.work(@interval)
          end
        end
      end

      # Traps signals TERM, INT and QUIT to stop the machine.
      def trap_signals
        ['TERM', 'INT', 'QUIT'].each { |signal| trap(signal) { stop } }
      end

      # Deletes worker information from Redis if there's now processes for
      # their pids.
      def prune_dead_workers
        @workers.first.prune_dead_workers if @workers.size > 0
      end

      # Shuts down the machine if all fibers are dead.
      def system_monitor
        Fiber.new do
          loop do
            EM.stop unless fibers.any?(&:alive?)
            EM::Synchrony.sleep 1
          end
        end
      end

      def create_pidfile
        File.open(@pidfile, 'w') { |f| f << Process.pid } if @pidfile
      end
    end
  end
end
