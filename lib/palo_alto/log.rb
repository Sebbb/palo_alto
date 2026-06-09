# frozen_string_literal: true

module PaloAlto
  # Palo Alto main class for XML
  class XML
    def log(**args)
      args.merge!({ client: self })
      Log.new(**args)
    end

    # Palo Alto main class for log access
    class Log
      include Enumerable

      attr_reader :count

      def initialize(client:, query:, log_type:, nlogs: 20, dir: :backward, show_detail: false, days: 7) # rubocop:disable Metrics/MethodLength,Metrics/ParameterLists
        @client = client
        @log_query_payload = {
          type: 'log',
          'log-type': log_type,
          nlogs: nlogs,
          dir: dir,
          'show-detail': show_detail ? 'yes' : 'no'
        }

        @log_query_payload[:query] =
          [query, days ? "(receive_time geq #{(Time.now - (days * 3600 * 24)).to_i})" : nil].compact.join(' AND ')

        run_query

        @first_result = fetch_result
        @enum = to_enum
      end

      def next
        @enum.next
      end

      def run_query # rubocop:disable Metrics/MethodLength
        retried = false
        begin
          result = @client.execute(@log_query_payload)
        rescue PaloAlto::InvalidCommandException => e
          unless retried
            retried = true
            retry
          end
          raise e
        end
        @job_id = result.at_xpath('response/result/job').text
        warn "#{@client.host} #{Time.now}: Got job id #{@job_id} for log query"

        @count = nil
        @skip = 0
      end

      def rewind
        @current_result = @first_result
        @skip = 0
        @enum = to_enum
      end

      def fetch_result # rubocop:disable Metrics/MethodLength,Metrics/AbcSize,Metrics/CyclomaticComplexity
        loop_running = false
        return nil if @count && @skip == @count

        i = 0
        loop do
          loop_running = true
          sleep 0.5 if i.positive?
          begin
            payload = {
              type: 'log',
              action: 'get',
              'job-id': @job_id,
              skip: @skip
            }
            @current_result = @client.execute(payload)
          rescue PaloAlto::UnknownErrorException => e
            if e.message == 'Query timed out'
              warn 'Retrying log query'
              run_query
              retry
            end
          end
          i += 1
          if @current_result.at_xpath('response/result/job/status').text == 'FIN'
            loop_running = false
            break
          end
        end
        loop_running = false

        @count = @current_result.at_xpath('response/result/job/cached-logs').text.to_i

        @current_result
      ensure
        if loop_running
          payload = {
            type: 'log',
            action: 'finish',
            'job-id': @job_id
          }
          @client.execute(payload)
        end
      end

      def each # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
        if @skip.positive? # in case #each is called again, e.g. because #first is called, reset all
          @current_result = @first_result
          @skip = 0
        end

        loop do
          @current_result.xpath('/response/result/log/logs/entry').each do |l|
            result = l.children.each_with_object({}) do |child, h|
              next h if child.is_a?(Nokogiri::XML::Text)

              h[child.name] = child.text
            end
            yield result
          end

          # skip already returned logs next time
          @skip += @current_result.at_xpath('response/result/log/logs/@count').value.to_i

          break unless fetch_result
        end
      end
    end
  end
end
