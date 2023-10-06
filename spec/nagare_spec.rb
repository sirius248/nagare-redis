# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NagareRedis do
  it 'has a version number' do
    expect(NagareRedis::VERSION).not_to be nil
  end
end
