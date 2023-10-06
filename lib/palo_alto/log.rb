# frozen_string_literal: true

module PaloAlto
  # Palo Alto main class for XML
  class XML
    def log(*args)
      args.last.merge!({ client: self })
      Log.new(*args)
    end

    # Palo Alto main class for log access
    class Log < Enumerator
      def initialize(client:, query:, log_type:, nlogs: 20, dir: :backward, show_detail: false, days: 7) # rubocop:disable Metrics/MethodLength,Metrics/ParameterLists
        @client = client
        @log_query_payload = {
          type: 'log',
          'log-type': log_type,
          nlogs: nlogs,
          query: query,
          dir: dir,
          'show-detail': show_detail ? 'yes' : 'no'
        }

        if days
          @log_query_payload[:query] += " AND (receive_time geq '#{(Time.now - days * 3600 * 24).strftime('%Y/%m/%d %H:%M:%S')}')"
        end

        run_query

        @first_result = fetch_result
        super
      end

      def run_query
        result = @client.execute(@log_query_payload)
        @job_id = result.at_xpath('response/result/job').text
        warn "#{@client.host} #{Time.now}: Got job id #{@job_id} for log query"

        @count = nil
        @skip = 0
      end

      def restore_first
        @current_result = @first_result
        @skip = @current_result.at_xpath('response/result/log/logs/@count').value.to_i
      end

      def rewind
        restore_first
        super
      end

      def fetch_result # rubocop:disable Metrics/MethodLength
        return nil if @count && @skip == @count

        i = 0
        loop do
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
          break if @current_result.at_xpath('response/result/job/status').text == 'FIN'
        end
        @count = @current_result.at_xpath('response/result/job/cached-logs').text.to_i

        @skip += @current_result.at_xpath('response/result/log/logs/@count').value.to_i # skip now shown logs
        @current_result
      end

      attr_reader :count

      def each(&block) # rubocop:disable Metrics/MethodLength
        # a bit buggy: after #to_a, without calling #rewind, I can't use #next reliable anymore

        restore_first if @skip.positive?
        loop do
          @current_result.xpath('/response/result/log/logs/entry').each do |l|
            result = l.children.each_with_object({}) do |child, h|
              next h if child.is_a?(Nokogiri::XML::Text)

              h[child.name] = child.text
            end
            block.call(result)
          end
          break unless fetch_result
        end
      end
    end
  end
end
