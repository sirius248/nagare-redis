# frozen_string_literal: true

require 'socket'

module Nagare
  ##
  # Abstraction layer for dealing with the basic RedisStreams X... commands
  # for interacting with streams, groups and consumers.
  #
  # This module may be mocked during testing if necessary, or replaced with
  # an implementation using other technology, like kafka, AciveMQ or others.
  #
  # Important: Groups are always assumed to be named `<stream>-<group>`.
  #            Consumers are always created using the hostname + thread id
  class RedisStreams
    class << self
      ##
      # Returns a connection to redis. Currently not pooled
      #
      # @return [Redis] a connection to redis from the redis-rb gem
      def connection
        # FIXME: Connection pool should come in handy
        @connection ||= Redis.new(url: Nagare::Config.redis_url)
      end

      ##
      # Determines wether a group already exists in redis or not using xinfo
      #
      # @param stream [String] name of the stream
      # @param group [String] name of the group
      #
      # @return [Boolean] true if the group exists, otherwise false
      # rubocop:disable Metrics/AbcSize
      def group_exists?(stream, group)
        stream = stream_name(stream)
        info = connection.xinfo(:groups, stream.to_s)
        info.any? { |line| line['name'] == "#{stream}-#{group}" }
      rescue Redis::CommandError => e
        logger.info "Seems the group doesn't exist"
        logger.info e.message
        logger.info e.backtrace.join("\n")
        false
      end
      # rubocop:enable Metrics/AbcSize

      ##
      # Creates a group in redis for the stream using xgroup
      #
      # @param stream [String] name of the stream
      # @param group [String] name of the group
      #
      # @return [String] OK
      def create_group(stream, group)
        stream = stream_name(stream)
        connection.xgroup(:create, stream, "#{stream}-#{group}", '$',
                          mkstream: true)
      end

      ##
      # Deletes a group in redis for the stream using xgroup
      #
      # @param stream [String] name of the stream
      # @param group [String] name of the group
      #
      # @return [String] OK
      def delete_group(stream, group)
        stream = stream_name(stream)
        connection.xgroup(:destroy, stream, "#{stream}-#{group}")
      end

      ##
      # Publishes an eevent to the specified stream
      #
      # @param stream [String] name of the stream
      # @param event_name [String] key of the event
      # @param data [String] data for the event, usually in JSON format.
      #
      # @return [String] message id
      def publish(stream, event_name, data)
        stream = stream_name(stream)
        connection.xadd(stream, { "#{event_name}": data })
      end

      ##
      # Reads the next messages from the consumer group in redis.
      #
      # @returns [Array] Array of tuples with [message-id, data_as_hash]
      def read_next_messages(stream, group)
        stream = stream_name(stream)
        result = connection.xreadgroup("#{stream}-#{group}",
                                       "#{hostname}-#{thread_id}", stream, '>')
        result[stream] || []
      end

      ##
      # Acknowledges a message as processed in the consumer group
      #
      # @param stream [String] name of the stream
      # @param group [String] name of the group
      # @param message_id [String] the id of the message
      #
      # @return [Integer] number of messages processed
      def mark_processed(stream, group, message_id)
        stream = stream_name(stream)
        group = "#{stream}-#{group}"

        count = connection.xack(stream, group, message_id)
        return if count == 1

        raise "Message could not be ACKed in Redis: #{stream} #{group} "\
          "#{message_id}. Return value: #{count}"
      end

      ##
      # Reads the last message on the stream without using a consumer group
      #
      # @param stream [String] name of the stream
      #
      # @return [Array] tuple of [message-id, event]
      def read_one(stream)
        stream = stream_name(stream)
        result = connection.xread(stream, [0], count: 1)
        result[stream]&.first
      end

      ##
      # Empties a stream for all readers, not only the consumer group
      #
      # @return [Integer] the number of entries actually deleted
      def truncate(stream)
        stream = stream_name(stream)
        connection.xtrim(stream, 0)
      end

      def stream_name(stream)
        suffix = Nagare::Config.suffix
        if suffix.nil?
          stream
        else
          "#{stream}-#{suffix}"
        end
      end

      ##
      # Query pending messages for a consumer group
      #
      # @return [Hash] {
      #   "size"=>0,
      #   "min_entry_id"=>nil,
      #   "max_entry_id"=>nil,
      #   "consumers"=>{}
      # }
      def pending(stream, group)
        stream = stream_name(stream)
        group = "#{stream}-#{group}"
        connection.xpending(stream, group)
      end

      private

      def logger
        Nagare.logger
      end

      def hostname
        Socket.gethostname
      end

      def thread_id
        Thread.current.object_id
      end
    end
  end
end
