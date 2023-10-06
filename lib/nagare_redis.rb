# frozen_string_literal: true

require 'logger'
require 'json'
require 'redis'
require 'nagare_redis/version'
require 'nagare_redis/config'
require 'nagare_redis/redis_streams'
require 'nagare_redis/listener'
require 'nagare_redis/publisher'
require 'nagare_redis/listener_pool'

#
# Nagare: Redis Streams wrapper for pub/sub with durable consumers
# see https://github.com/vavato-be/nagare
module NagareRedis
  class << self
    attr_writer :logger

    def logger
      @logger ||= Logger.new($stdout).tap do |log|
        log.progname = name
      end
    end
  end
end
