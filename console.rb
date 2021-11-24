#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler'
Bundler.require(:default, :development)

Dotenv.load('.env')

require_relative './lib/palo_alto'

client = PaloAlto::XML.new(
  host: ENV['PALO_ALTO_HOST'],
  port: '443',
  username: ENV['PALO_ALTO_USER'],
  password: ENV['PALO_ALTO_PASSWORD'],
  debug: ENV['PALO_ALTO_DEBUG']&.split(/\s/)&.map(&:to_sym) || []
)


IRB.start
