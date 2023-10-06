# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NagareRedis do
  let(:publisher) do
    Class.new do
      include NagareRedis::Publisher
      stream 'nagare_integration_stream'

      def do_something
        publish(:something_happened, { foo: 'bar' })
      end
    end
  end

  let(:listener) do
    Class.new(NagareRedis::Listener) do
      stream 'nagare_integration_stream'

      class << self
        attr_writer :invoked

        def invoked
          @invoked ||= false
        end
      end

      def self.name
        'IntegrationTestListener'
      end

      def something_happened(_event)
        self.class.invoked = true
      end
    end
  end

  before do
    NagareRedis::RedisStreams.truncate('nagare_integration_stream')

    NagareRedis::Config.configure do |config|
      config.redis_url = "redis://#{ENV['REDIS_URL'] || 'localhost'}:#{ENV['REDIS_PORT'] || '6379'}"
      config.group_name = 'nagare_integration_group'
    end
  end

  context 'when a publisher publishes a message' do
    it 'invokes the listener when the message is received' do
      listener
      publisher.new.do_something
      NagareRedis::ListenerPool.poll
      expect(listener.invoked).to eq true
    end
  end
end
