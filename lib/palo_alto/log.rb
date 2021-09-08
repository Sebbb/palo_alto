require "pp"

module PaloAlto
	class XML

		def log(*x)
			Log.new(*x)
		end

		class Log < Enumerator
			def initialize(query:, log_type:, nlogs: 20, dir: :backward, show_detail: false, days: 7)

				payload = {
					type:       'log',
					'log-type': log_type,
					nlogs:      nlogs,
					query:      !days ? query : query + " AND (receive_time geq '#{(Time.now-days*3600*24).strftime("%Y/%m/%d %H:%M:%S")}')",
					dir:        dir,
					'show-detail': show_detail ? 'yes' : 'no'
				}
				result = XML.execute(payload)
				@job_id = result.at_xpath('response/result/job').text
				@count=nil
				@skip=0
				@first_result = fetch_result
				#pp @current_result
				super
			end

			def restore_first
				@current_result = @first_result
				@skip = @current_result.at_xpath("response/result/log/logs/@count").value.to_i
			end

			def rewind
				restore_first
				super
			end

			def fetch_result
				return nil if @count && @skip == @count

				payload = {
					type:     'log',
					action:   'get',
					'job-id': @job_id,
					skip:     @skip
				}

				i=0
				begin
					sleep 0.5 if i>0
					@current_result = XML.execute(payload)
					i+=1
				end until @current_result.at_xpath("response/result/job/status").text == 'FIN'
				@count = @current_result.at_xpath("response/result/job/cached-logs").text.to_i

				@skip += @current_result.at_xpath("response/result/log/logs/@count").value.to_i # skip now shown logs
				@current_result
			end

			def count
				@count
			end

			def each(&block)
				# a bit buggy: after #to_a, without calling #rewind, I can't use #next reliable anymore

				if @skip>0
					restore_first
				end
				begin
					@current_result.xpath("/response/result/log/logs/entry").each{|l|
						result = l.children.inject({}){|h, child|
							next h if child.is_a?(Nokogiri::XML::Text)
							h[child.name] = child.text
							h
						}
						block.call(result)
					}
				end while fetch_result
			end
		end
	end
end

