#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler'
Bundler.require(:default, :development)

Dotenv.load('.env')

require_relative 'lib/palo_alto'

client = PaloAlto::XML.new(
  host: ENV.fetch('PALO_ALTO_HOST', nil),
  username: ENV.fetch('PALO_ALTO_USER', nil),
  password: ENV.fetch('PALO_ALTO_PASSWORD', nil),
  debug: ENV['PALO_ALTO_DEBUG']&.split(/\s/)&.map(&:to_sym) || []
)

IRB.setup(nil)
workspace = IRB::WorkSpace.new(binding)
irb = IRB::Irb.new(workspace)

IRB.conf[:MAIN_CONTEXT] = irb.context
irb.eval_input
