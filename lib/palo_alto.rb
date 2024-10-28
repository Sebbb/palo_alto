# frozen_string_literal: true

require 'openssl'
require 'nokogiri'
require 'net/http'

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

  class UnknownErrorException < TemporaryException
  end

  class BadXpathException < PermanentException
  end

  class ObjectNotPresentException < PermanentException
  end

  class ObjectNotFoundException < PermanentException
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
      @global_lock = Mutex.new

      def self.make_request(opts)
        options = {}
        options[:verify_ssl] ||= OpenSSL::SSL::VERIFY_PEER

        headers = {
          'User-Agent': 'ruby-keystone-client',
          'Accept': 'application/xml',
          'Content-Type': 'application/x-www-form-urlencoded'
        }

        # merge in settings from method caller
        options = options.merge(opts)
        options[:headers].merge!(headers)

        http_client = nil

        @global_lock.synchronize do
          Thread.current[:http_clients] ||= {}

          unless (http_client = Thread.current[:http_clients][options[:host]])
            http_client = Net::HTTP.new(options[:host], 443)
            http_client.use_ssl = true
            http_client.verify_mode = options[:verify_ssl]
            http_client.read_timeout = http_client.open_timeout = (options[:timeout] || 60)
            http_client.set_debug_output(options[:debug].include?(:http) ? $stdout : nil)
            Thread.current[:http_clients][options[:host]] = http_client
          end
        end

        payload = options[:payload]
        post_req = Net::HTTP::Post.new('/api/', options[:headers])

        if payload.values.any? { |value| [IO, StringIO].any? { |t| value.is_a?(t) } }
          payload.values.select { |value| [IO, StringIO].any? { |t| value.is_a?(t) } }.each(&:rewind)
          post_req.set_form(payload.map { |k, v| [k.to_s, v] }, 'multipart/form-data')
        else
          post_req.set_form_data(payload)
        end

        http_client.start unless http_client.started?

        response = http_client.request(post_req)

        case response.code
        when '200'
          return response.body
        when '401'
          raise SessionTimedOutException
        when '400', '403'
          begin
            pp [:error, options[:host], response.code, response.message]
            data = Nokogiri::XML.parse(response.body)
            message = data.xpath('//response/response/msg').text
            code = response.code.to_i
          rescue StandardError
            raise ConnectionErrorException, "#{response.code} #{response.message}"
          end
          raise_error(code, message)
        else
          raise ConnectionErrorException, "#{response.code} #{response.message}"
        end

        nil
      rescue Net::OpenTimeout, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::ECONNRESET => e
        raise ConnectionErrorException, [e.message, options[:host]].inspect
      end

      def self.raise_error(code, message)
        error = case code
                when 400 then BadRequestException
                when 403 then ForbiddenException
                when 1 then UnknownCommandException
                when 6 then BadXpathException
                when 7 then ObjectNotPresentException
                when 8 then ObjectNotUniqueException
                when 10 then ReferenceCountNotZeroException
                when 12 then InvalidObjectException
                when 13 then ObjectNotFoundException
                when 14 then OperationNotPossibleException
                when 15 then OperationDeniedException
                when 16 then UnauthorizedException
                when 17 then InvalidCommandException
                when 18 then MalformedCommandException
                when 19..20 then SuccessException
                when 22 then SessionTimedOutException
                when 2..5, 11, 21 then InternalErrorException
                else UnknownErrorException
                end
        raise error, message
      end
    end
  end

  class XML
    attr_accessor :host, :username, :auth_key, :verify_ssl, :debug, :timeout

    def pretty_print_instance_variables
      super - %i[@password @subclasses @subclasses @expression @arguments @cache @op @auth_key]
    end

    @@output_lock = Mutex.new

    def print_sent(options, method = :puts)
      @@output_lock.synchronize do
        send(method, "Sent (#{Time.now}, #{options[:session_id]}):")
        options.each do |k, v|
          case k
          when :debug
            send(method, " #{k}: #{v.reject { |str| str.start_with?('_') }.join(', ')}")
          when :headers
            headers = options[:headers].dup.transform_keys(&:to_s)
            headers['X-PAN-KEY'] = '***' if headers.key?('X-PAN-KEY')
            puts " #{k}: #{headers}"
          when :payload
            send(method, ' payload: ' + options[:payload].map do |k, v|
              element_length = 1024
              if k == :element && v.length >= element_length
                [k.to_s, "#{v[..element_length]}..."]
              elsif k == :password
                [k.to_s, '***']
              else
                [k.to_s, v]
              end
            end.to_h.inspect)
          else
            send(method, " #{k}: #{v}")
          end
        end
      end
    end

    def execute(payload, skip_authentication: false, skip_cache: false)
      get_auth_key if !auth_key && !skip_authentication
      session_id = (0...6).map { ('a'..'z').to_a[rand(26)] }.join

      if payload[:type] == 'config' && !skip_cache
        if payload[:action] == 'get'
          start_time = Time.now
          @cache.each do |cached_xpath, cache|
            search_xpath = payload[:xpath].sub('/descendant::device-group[1]/', '/device-group/')
            next unless search_xpath.start_with?(cached_xpath)

            remove = cached_xpath.split('/')[1...-1].join('/').length
            new_xpath = "response/result/#{search_xpath[(remove + 2)..]}"

            results = cache.xpath(new_xpath)
            xml = Nokogiri.parse("<?xml version=\"1.0\"?><response><result>#{results}</result></response>")

            if debug.include?(:statistics)
              warn "Elapsed for parsing cache: #{Time.now - start_time} seconds (#{session_id})"
            end

            return xml
          end
        elsif !@keep_cache_on_edit
          @cache = {}
        end
      end

      retried = 0
      begin
        # configure options for the request
        options = {}
        options[:host]       = host
        options[:session_id] = session_id
        options[:verify_ssl] = verify_ssl
        options[:payload]    = payload
        options[:debug]      = debug
        options[:timeout]    = timeout || 600
        options[:headers]    = if payload[:type] == 'keygen'
                                 {}
                               else
                                 { 'X-PAN-KEY': auth_key }
                               end

        print_sent(options) if debug.include?(:sent)

        start_time = Time.now
        text = Helpers::Rest.make_request(options)

        @@output_lock.synchronize do
          if debug.include?(:statistics)
            warn "Elapsed for API call #{payload[:type]}/#{payload[:action] || '(unknown action)'} on #{host}: #{Time.now - start_time} seconds, #{text.length} bytes (#{session_id})"
          end

          warn "Received at #{Time.now} (#{session_id}):\n#{text.inspect}\n" if debug.include?(:received)
        end

        data = Nokogiri::XML.parse(text)
        unless data.xpath('//response/@status').to_s == 'success'
          unless %w[op commit].include?(payload[:type]) # here we fail silent
            warn "Command failed on host #{host} at #{Time.now} (#{session_id})"
            print_sent(options, :warn) if debug.include?(:sent_on_error) && !debug.include?(:sent)
            if debug.include?(:received_on_error) && !debug.include?(:received)
              @@output_lock.synchronize do
                warn "Received at #{Time.now} (#{session_id}):\n#{text.inspect}\n"
              end
            end
          end
          code = data.at_xpath('//response/@code')&.value.to_i # sometimes there is no code :( e.g. for 'op' errors
          message = data.xpath('/response/msg/line').map(&:text).map(&:strip).join("\n")
          Helpers::Rest.raise_error(code, message)
        end

        data
      rescue ConnectionErrorException => e
        # for ConnectionErrorException, you don't know if the command was successful as you don't get a result after an action started:(
        # As it's a temporary error, we need to rescue/raise it explicitly
        # #edit! rescues it, for other calls, it normally should not happen.....
        raise e
      rescue EOFError, Net::ReadTimeout => e
        max_retries = if %w[keygen config].include?(payload[:type])
                        # TODO: only retry on config, when it's get or edit, otherwise you may get strange errors
                        40
                      else
                        0
                      end

        if retried >= max_retries
          raise ConnectionErrorException, [e.message, options[:host], payload[:type]].inspect
        end

        retried += 1
        if debug.include?(:warnings)
          @@output_lock.synchronize do
            warn "Got connection error #{e.inspect} from #{host}; retrying (try #{retried} of #{max_retries}, #{session_id})"
          end
        end
        sleep 10
        retry
      rescue TemporaryException => e
        dont_retry_at = [
          'Partial revert is not allowed. Full system commit must be completed.',
          'Local commit jobs are queued. Revert operation is not allowed.',
          'Config for scope ',
          'Config is not currently locked for scope ',
          'Commit lock is not currently held by',
          'You already own a config lock for scope ',
          'This operation is blocked because of ',
          'Other administrators are holding config locks ',
          'Configuration is locked by ',
          'device-group', #  device-group -> ... is already in use
          ' device-group' #  device-group -> ... is already in use
        ]

        max_retries = if dont_retry_at.any? { |str| e.message.start_with?(str) }
                        0
                      elsif e.message.start_with?('Timed out while getting config lock. Please try again.')
                        40
                      else
                        1
                      end

        raise e if retried >= max_retries

        retried += 1
        if debug.include?(:warnings)
          @@output_lock.synchronize do
            warn "Got temporary error #{e.inspect}; retrying (try #{retried} of #{max_retries})"
          end
        end

        get_auth_key if e.is_a?(SessionTimedOutException)
        retry
      end
    end

    def clear_cache!
      @cache = {}
      @keep_cache_on_edit = nil
    end

    def keep_cache_on_edit!
      @keep_cache_on_edit = true
    end

    def cache!(xpath)
      cached_xpath = xpath.is_a?(String) ? xpath : xpath.to_xpath

      payload = {
        type: 'config',
        action: 'get',
        xpath: cached_xpath
      }

      @cache[cached_xpath] = execute(payload, skip_cache: true)
      true
    end

    def commit!(all: false, device_groups: nil, templates: nil,
                admins: [username],
                raw_result: false,
                wait_for_completion: true, wait: 5, timeout: 60 * 20)
      return nil if device_groups.is_a?(Array) && device_groups.empty? && templates.is_a?(Array) && templates.empty?

      cmd = if all
              'commit'
            else
              commit_partial = {
                'no-template-stack': true,
                'no-log-collector': true,
                'no-log-collector-group': true,
                'no-wildfire-appliance': true,
                'no-wildfire-appliance-cluster': true,
                'device-and-network': 'excluded',
                'shared-object': 'excluded'
              }

              if device_groups
                commit_partial.merge!(device_groups.empty? ? { 'no-device-group': true } : { 'device-group': device_groups })
              end

              if templates
                commit_partial.merge!(templates.empty? ? { 'no-template': true } : { template: templates })
              end

              commit_partial.merge!({ admin: admins }) if admins

              { commit: { partial: commit_partial } }
            end

      result = op.execute(cmd)

      return result if raw_result

      job_id = result.at_xpath('response/result/job')&.text
      return result unless job_id && wait_for_completion

      wait_for_job_completion(job_id, wait: wait, timeout: timeout) if job_id
    end

    def full_commit_required?
      result = op.execute({ check: 'full-commit-required' })
      return true unless result.at_xpath('response/result').text == 'no'

      false
    end

    def primary_active?
      cmd = { show: { 'high-availability': 'state' } }
      state = op.execute(cmd)
      state.at_xpath('response/result/local-info/state')&.text == 'primary-active'
    end

    # area: config, commit
    def show_locks(area:)
      cmd = { show: "#{area}-locks" }
      ret = op.execute(cmd)
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
      raise MalformedCommandException, 'No type specified' if location && !type

      if block_given?
        return false unless lock(area: area, comment: comment, type: type, location: location)

        begin
          return yield
        ensure
          unlock(area: area, type: type, location: location)
        end
      end

      begin
        cmd = { request: { "#{area}-lock": { add: { comment: comment || '(null)' } } } }
        op.execute(cmd, type: type, location: location)
        true
      rescue PaloAlto::UnknownErrorException => e
        return true if e.message.start_with?('You already own a config lock for scope ') ||
                       e.message == "Config for scope shared is currently locked by #{username}" ||
                       e.message == "Config for scope #{location} is currently locked by #{username}"

        false
      end
    end

    def unlock(area:, type: nil, location: nil, name: nil)
      begin
        cmd = if name
                { request: { "#{area}-lock": { remove: { admin: name } } } }
              else
                { request: { "#{area}-lock": 'remove' } }
              end
        op.execute(cmd, type: type, location: location)
      rescue PaloAlto::UnknownErrorException => e
        return true if e.message.start_with?('Config is not currently locked')

        return false
      end
      true
    end

    def remove_all_locks
      %w[config commit].each do |area|
        show_locks(area: area).each do |lock|
          unlock(area: area, type: lock[:type], location: lock[:location], name: area == 'commit' ? lock[:name] : nil)
        end
      end
    end

    def check_for_changes(admins: [username])
      cmd = if admins
              { show: { config: { list: { 'change-summary': { partial: { admin: admins } } } } } }
            else
              { show: { config: { list: 'change-summary' } } }
            end
      result = op.execute(cmd)
      {
        device_groups: result.xpath('response/result/summary/device-group/member').map(&:inner_text),
        templates: result.xpath('response/result/summary/template/member').map(&:inner_text)
      }
    end

    # returns nil if job isn't finished yet, otherwise the job result
    def query_and_parse_job(job_id)
      cmd = { show: { jobs: { id: job_id } } }
      result = op.execute(cmd)
      status = result.at_xpath('response/result/job/status')&.text
      return result unless %w[ACT PEND].include?(status)

      nil
    rescue StandardError => e
      warn [:job_query_error, @host, e].inspect
      false
    end

    # returns true if successful
    # returns nil if not completed yet
    # otherwise returns the error
    def commit_successful?(commit_result)
      if commit_result.at_xpath('response/msg')&.text&.start_with?('The result of this commit would be the same as the previous commit queued/processed') ||
         commit_result.at_xpath('response/msg')&.text == 'There are no changes to commit.'
        return true
      end

      job_id = commit_result.at_xpath('response/result/job')&.text
      unless job_id
        warn [:no_job_id, result].inspect
        return false
      end

      job_result = query_and_parse_job(job_id)
      return job_result unless job_result # can be either nil or false (errored)

      if job_result.xpath('response/result/job/details/line').text&.include?('Configuration committed successfully')
        return true
      end

      job_result
    end

    def wait_for_job_completion(job_id, wait: 5, timeout: 20 * 60)
      cmd = { show: { jobs: { id: job_id } } }
      start = Time.now
      loop do
        begin
          result = op.execute(cmd)
          status = result.at_xpath('response/result/job/status')&.text
          return result unless %w[ACT PEND].include?(status)
        rescue StandardError => e
          warn [:job_query_error, Time.now, @host, e].inspect
          return false if e.message =~ /\Ajob \d+ not found\z/
        end
        sleep wait
        break unless start + timeout > Time.now
      end
      warn [:job_query_error, Time.now, @host, :timeout].inspect
      false
    end

    # wait: how long revert is retried (every 10 seconds)
    def revert!(all: false, wait: 60)
      cmd = if all
              { revert: 'config' }
            else
              { revert: { config: { partial: {
                admin: [username],
                'no-template': true,
                'no-template-stack': true,
                'no-log-collector': true,
                'no-log-collector-group': true,
                'no-wildfire-appliance': true,
                'no-wildfire-appliance-cluster': true,
                'device-and-network': 'excluded',
                'shared-object': 'excluded'
              } } } }
            end

      waited = 0
      begin
        op.execute(cmd)
      rescue StandardError => e
        puts 'Revert failed; waiting and retrying'
        sleep 10
        waited += 1
        retry while waited < wait
        raise e
      end
    end

    def initialize(host:, username:, password:, verify_ssl: OpenSSL::SSL::VERIFY_NONE, debug: [])
      @host       = host
      @username   = username
      @password   = password
      @verify_ssl = verify_ssl
      @debug      = debug

      @subclasses = {}

      @cache = {}

      # xpath
      @expression = :root
      @arguments = [Expression.new(:this_node), []]
    end

    # Perform a query to the API endpoint for an auth_key based on the credentials provided
    def get_auth_key
      # establish the required options for the key request
      payload = { type: 'keygen',
                  user: username,
                  password: @password }

      # get and parse the response for the key
      xml_data = execute(payload, skip_authentication: true)
      self.auth_key = xml_data.xpath('//response/result/key')[0].content
    end
  end
end
