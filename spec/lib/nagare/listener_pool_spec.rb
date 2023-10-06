# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NagareRedis::ListenerPool do
  let(:stream) { 'listener_pool_spec' }
  let(:group) { 'listener_pool_spec_group' }
  let(:listener) { instance_double(NagareRedis::Listener, handle_event: nil) }
  let(:listener_class) { class_double(NagareRedis::Listener, new: listener) }

  before do
    allow(NagareRedis::Config).to receive(:group_name).and_return(group)
    allow(NagareRedis::RedisStreams).to receive(:claim_next_stuck_message).and_return([])
    allow(NagareRedis::RedisStreams).to receive(:group_exists?).and_return(true)
  end

  describe '.start_listening' do
    let(:thread) { described_class.start_listening }

    before do
      allow(described_class).to receive(:poll)
      thread
    end

    after do
      Thread.kill(thread)
    end

    it 'starts a thread to poll redis' do
      sleep(1)
      expect(described_class).to have_received(:poll).at_least(:once)
    end
  end

  describe '.poll' do
    context 'when there are listeners registered but no new events' do
      before do
        allow(described_class).to receive(:listener_pool).and_return({ 'listener_pool_spec': [listener_class] })
        allow(NagareRedis::RedisStreams).to receive(:read_next_messages).and_return([])
        described_class.poll
      end

      it 'does not invoke listeners' do
        expect(listener).not_to have_received(:handle_event)
      end
    end

    context 'when there are listeners registered and new events in the stream' do
      let(:event) { { foo: 'bar' } }
      let(:message_id) { 'message_id-0' }

      before do
        allow(described_class).to receive(:listener_pool).and_return({ 'listener_pool_spec': [listener_class] })
      end

      context 'when the listener processes the event without raising errors' do
        before do
          allow(NagareRedis::RedisStreams).to receive(:read_next_messages)
            .and_return([[message_id, event]])
          allow(NagareRedis::RedisStreams).to receive(:mark_processed)
          described_class.poll
        end

        it 'invokes #handle_event on the listener, passing in the event' do
          expect(listener).to have_received(:handle_event).with(event)
        end

        it 'marks the message as processed (ACK) with the redis streams group' do
          expect(NagareRedis::RedisStreams).to have_received(:mark_processed).with(
            stream.to_sym, group, message_id
          )
        end
      end

      context 'when the listener raises an error' do
        before do
          allow(described_class).to receive(:listener_pool).and_return({ 'listener_pool_spec': [listener_class] })
          allow(NagareRedis::RedisStreams).to receive(:read_next_messages)
            .and_return([[message_id, event]])
          allow(NagareRedis::RedisStreams).to receive(:mark_processed)
          allow(listener).to receive(:handle_event).and_raise('Processing error')

          described_class.poll
        end

        it 'invokes #handle_event on the listener, passing in the event' do
          expect(listener).to have_received(:handle_event).with(event)
        end

        it 'does NOT mark the message as processed (ACK) with the redis streams group' do
          expect(NagareRedis::RedisStreams).not_to have_received(:mark_processed).with(
            stream.to_sym, group, message_id
          )
        end
      end
    end

    context 'when there are listeners registered and a pending event in the stream' do
      let(:event) { { foo: 'bar' } }
      let(:message_id) { 'message_id-0' }

      before do
        allow(described_class).to receive(:listener_pool).and_return({ 'listener_pool_spec': [listener_class] })
      end

      context 'when the listener processes the event without raising errors' do
        before do
          allow(NagareRedis::RedisStreams).to receive(:claim_next_stuck_message)
            .and_return([[message_id, event]])
          allow(NagareRedis::RedisStreams).to receive(:read_next_messages)
          allow(NagareRedis::RedisStreams).to receive(:mark_processed)
          described_class.poll
        end

        it 'invokes #handle_event on the listener, passing in the event' do
          expect(listener).to have_received(:handle_event).with(event)
        end

        it 'marks the message as processed (ACK) with the redis streams group' do
          expect(NagareRedis::RedisStreams).to have_received(:mark_processed).with(
            stream.to_sym, group, message_id
          )
        end

        it 'does not try to read the next message from the stream' do
          expect(NagareRedis::RedisStreams).not_to have_received(:read_next_messages)
        end
      end
    end
  end
end
