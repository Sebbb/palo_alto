# frozen_string_literal: true

require 'openssl'
require 'nokogiri'
require 'net/http'
require 'pp'

require_relative 'palo_alto/version'

require_relative 'palo_alto/config'
require_relative 'palo_alto/log'
require_relative 'palo_alto/op'

module PaloAlto
  class PermanentException < StandardError
  end

  class TemporaryException < StandardError
  end

  class ConnectionErrorException < TemporaryException
  end

  class BadRequestException < PermanentException
  end

  class ForbiddenException < PermanentException
  end

  class UnknownCommandException < PermanentException
  end

  class InternalErrorsException < TemporaryException
  end

  class BadXpathException < PermanentException
  end

  class ObjectNotPresentException < PermanentException
  end

  class ObjectNotUniqueException < PermanentException
  end

  class ReferenceCountNotZeroException < PermanentException
  end

  class InvalidObjectException < PermanentException
  end

  class OperationNotPossibleException < PermanentException
  end

  class OperationDeniedException < PermanentException
  end

  class UnauthorizedException < PermanentException
  end

  class InvalidCommandException < PermanentException
  end

  class MalformedCommandException < PermanentException
  end

  class SuccessException < PermanentException
  end

  class InternalErrorException < TemporaryException
  end

  class SessionTimedOutException < TemporaryException
  end
  
  module Helpers
    class Rest
      def self.make_request(opts)
        options                            = {}
        options[:verify_ssl]              = OpenSSL::SSL::VERIFY_PEER
        options[:timeout]                  = 60

        headers                  = {}
        headers['User-Agent']    = 'ruby-keystone-client'
        headers['Accept']        = 'application/xml'
        headers['Content-Type'] = 'application/x-www-form-urlencoded'

        # merge in settings from method caller
        options = options.merge(opts)
        options[:headers].merge!(headers)

        thread = Thread.current
        unless thread[:http]
          thread[:http] = Net::HTTP.new(options[:host], options[:port])
          thread[:http].use_ssl = true
          thread[:http].verify_mode = options[:verify_ssl]
          thread[:http].read_timeout = thread[:http].open_timeout = options[:timeout]
          thread[:http].set_debug_output($stdout) if XML.debug.include?(:http)
        end

        thread[:http].start unless thread[:http].started?

        response = thread[:http].post('/api/', URI.encode_www_form(options[:payload]), options[:headers])

        if response.code == '200'
          return response.body
        elsif response.code == '400' or response.code == '403'
          begin
            data = Nokogiri::XML.parse(response.body)
            message = data.xpath('//response/response/msg').text
            code = response.code.to_i
          rescue
            raise ConnectionErrorException, "#{response.code} #{response.message}"
          end
          raise_error(code, message)
        else
          raise ConnectionErrorException, "#{response.code} #{response.message}"
        end
        nil

      rescue Net::OpenTimeout, Errno::ECONNREFUSED => e
        raise ConnectionErrorException, e.message
      end

      def self.raise_error(code, message)
        error = case code
                when 400 then BadRequestException
                when 403 then ForbiddenException
                when 1 then UnknownCommandException
                when 2..5 then InternalErrorsException
                when 6 then BadXpathException
                when 7 then ObjectNotPresentException
                when 8 then ObjectNotUniqueException
                when 10 then ReferenceCountNotZeroException
                when 0, 11, 21 then InternalErrorException # also if there is no code..
                when 12 then InvalidObjectException
                when 14 then OperationNotPossibleException
                when 15 then OperationDeniedException
                when 16 then UnauthorizedException
                when 17 then InvalidCommandException
                when 18 then MalformedCommandException
                when 19..20 then SuccessException
                when 22 then SessionTimedOutException
                else InternalErrorException
        end
        raise error, message
      end

      def self.execute(payload, headers: {})
        retried = false
        # configure options for the request
        options = {}
        options[:host]     = XML.host
        options[:port]     = XML.port
        options[:verify_ssl] = XML.verify_ssl
        options[:payload] = payload
        options[:headers] = headers

        if XML.debug.include?(:sent)
          warn "sent: (#{Time.now}\n#{options.pretty_inspect}\n"
        end

        start_time = Time.now
        text = Helpers::Rest.make_request(options)
        if XML.debug.include?(:statistics)
          warn "Elapsed for API call #{payload[:type]}/#{payload[:action]||'(unknown action)'}: #{Time.now-start_time} seconds"
        end

        if XML.debug.include?(:received)
          warn "received: #{Time.now}\n#{text}\n"
        end

        data = Nokogiri::XML.parse(text)
        unless data.xpath('//response/@status').to_s == 'success'
          if XML.debug.include?(:sent_on_error)
            warn "sent:\n#{options.inspect}\n"
          end
          if XML.debug.include?(:received_on_error)
            warn "received:\n#{text.inspect}\n"
          end
          code = data.at_xpath('//response/@code')&.value.to_i # sometimes there is no code :( e.g. for 'op' errors
          message = data.xpath('/response/msg/line').map(&:text).map(&:strip).join("\n")
          raise_error(code, message)
        end

        return data
      end

    end
  end

  class XML
    class << self
      attr_accessor :host, :port, :username, :password, :auth_key, :verify_ssl, :debug

      def execute(payload)
        retried = false
        begin
          Helpers::Rest.execute(payload, headers: {'X-PAN-KEY': self.auth_key})
        rescue TemporaryException => e
          dont_continue_at = [
            'Partial revert is not allowed. Full system commit must be completed.',
            'Config for scope '
          ]
          unless retried || dont_continue_at.any? { |x| e.message.start_with?(x) }
            if XML.debug.include?(:warnings)
              warn "Got error #{e.inspect}; retrying"
            end
            retried = true
            if e.is_a?(SessionTimedOutException)
              get_auth_key
            end
            retry
          else
            raise e
          end
        end
      end
    end

    def commit!(all: false, device_groups: nil, wait_for_completion: true)
      return nil if device_groups.is_a?(Array) && device_groups.empty?

      op = if all
             'commit'
           else
             { commit: { partial: [
               { 'admin': [XML.username] },
               device_groups ? {'device-group': device_groups } : nil,
               'no-template',
               'no-template-stack',
               'no-log-collector',
               'no-log-collector-group',
               'no-wildfire-appliance',
               'no-wildfire-appliance-cluster',
               { 'device-and-network': 'excluded' },
               { 'shared-object': 'excluded' }
             ].compact } }
           end
      Op.new.execute(op).tap do |result|
        if wait_for_completion
          job_id = result.at_xpath('response/result/job')&.text
          wait_for_job_completion(job_id) if job_id
        end
      end
    end

    def full_commit_required?
      result = Op.new.execute({check: 'full-commit-required'})
      return true unless result.at_xpath('response/result').text == 'no'

      false
    end

    def primary_active?
      cmd = {show: {'high-availability': 'state'}}
      state = Op.new.execute(cmd)
      state.at_xpath("response/result/local-info/state").text == "primary-active"
    end

    # area: config, commit
    def show_locks(area:)
      cmd = {show: "#{area}-locks"}
      ret = Op.new.execute(cmd)
      ret.xpath("response/result/#{area}-locks/entry").map do |lock|
        comment = lock.at_xpath('comment').inner_text
        location = lock.at_xpath('name').inner_text
        {
          name: lock.attribute('name').value,
          location: location == 'shared' ? nil : location,
          type: lock.at_xpath('type').inner_text,
          comment: comment == '(null)' ? nil : comment
        }
      end
    end

    # will execute block if given and unlock afterwards. returns false if lock could not be aquired
    def lock(area:, comment: nil, type: nil, location: nil)
      if block_given?
        if lock(area: area, comment: comment, type: type, location: location)
          begin
            return yield
          ensure
            unlock(area: area, type: type, location: location)
          end
        else
          return false
        end
      end

      begin
        cmd = {request: {"#{area}-lock": {add: {comment: comment || '(null)' }}}}
        Op.new.execute(cmd, get_extra_argument(type: type, location: location))
        true
      rescue PaloAlto::InternalErrorException
        false
      end
    end

    def unlock(area:, type: nil, location: nil)
      begin
        cmd = {request: {"#{area}-lock": 'remove'}}
        Op.new.execute(cmd, get_extra_argument(type: type, location: location))
      rescue PaloAlto::InternalErrorException
        return false
      end
      true
    end

    def remove_all_locks
      %w(config commit).each do |area|
        show_locks(area: area).each {|lock|
          unlock(area: area, type: lock[:type], location: lock[:location])
        }
      end
    end

    def check_for_changes(usernames: [XML.username])
      result = Op.new.execute({show: {config: {list: {'change-summary': {partial: {admin: usernames}}}}}})
      result.xpath('response/result/summary/device-group/member').map(&:inner_text)
    end

    def wait_for_job_completion(job_id, wait: 5, timeout: 300)
      cmd = {show: {jobs: {id: job_id}}}
      start = Time.now
      begin
        result = Op.new.execute(cmd)
        unless result.at_xpath('response/result/job/status')&.text=='ACT'
          return result
        end
        sleep wait
      end while start+timeout > Time.now
      return false
    end

    def revert!(all: false)
      op = if all
             { revert: 'config' }
           else
             { revert: { config: { partial: [
               { 'admin': [XML.username] },
               'no-template',
               'no-template-stack',
               'no-log-collector',
               'no-log-collector-group',
               'no-wildfire-appliance',
               'no-wildfire-appliance-cluster',
               { 'device-and-network': 'excluded' },
               { 'shared-object': 'excluded' }
             ] } } }
           end
      Op.new.execute(op)
    end

    def initialize(host:, port:, username:, password:, debug: [])
      self.class.host      = host
      self.class.port      = port
      self.class.username = username
      self.class.password = password
      self.class.verify_ssl = OpenSSL::SSL::VERIFY_NONE
      self.class.debug = debug

      @subclasses = {}

      # xpath
      @expression = :root
      @arguments = [Expression.new(:this_node), []]

      # attempt to obtain the auth_key
      #raise 'Exception attempting to obtain the auth_key' if (self.class.auth_key = get_auth_key).nil?
      self.class.get_auth_key

      self
    end

    # Perform a query to the API endpoint for an auth_key based on the credentials provided
    def self.get_auth_key

      # establish the required options for the key request
      payload = { type: 'keygen',
                  user: self.username,
                  password: self.password }

      # get and parse the response for the key
      xml_data = Helpers::Rest.execute(payload)
      self.auth_key = xml_data.xpath('//response/result/key')[0].content
    end

    private

    # used to limit an op command to a specifc dg/template
    def get_extra_argument(type:, location:)
      case type
        when 'dg'  then {vsys: location}
        when 'tpl' then raise
        else {}
      end
    end

  end
end
