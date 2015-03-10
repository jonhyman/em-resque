require 'resque'
require 'em-synchrony'
require 'em-synchrony/connection_pool'
require 'uri'

module EM::Resque
  extend Resque

  def self.initialize_redis(server, namespace = :resque, pool_size = 1)
    case server
      when String
      uri = URI.parse(server)
      redis = EventMachine::Synchrony::ConnectionPool.new(:size => pool_size) do
        Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
      end

      Resque.redis = Redis::Namespace.new(namespace, :redis => redis)
    when Redis::Namespace
      Resque.redis = server
    else
      redis = EventMachine::Synchrony::ConnectionPool.new(:size => pool_size) do
        server
      end
      Resque.redis = Redis::Namespace.new(namespace, :redis => redis)
    end
  end
end
