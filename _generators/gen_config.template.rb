require 'openssl'
require 'nokogiri'

module PaloAlto

	# https://github.com/teamcapybara/xpath - MIT license
	module DSL
		def relative(*expressions)
			Expression.new(:relative, current, expressions)
		end

		def root(*expressions)
			Expression.new(:root, current, expressions)
		end

		def current
			Expression.new(:this_node)
		end

		def descendant(*expressions)
			Expression.new(:descendant, current, expressions)
		end

		def child(*expressions)
			Expression.new(:child, current, expressions)
		end

		def axis(name, *element_names)
			Expression.new(:axis, current, name, element_names)
		end

		def anywhere(*expressions)
			Expression.new(:anywhere, expressions)
		end

		def xpath_attr(expression)
			Expression.new(:attribute, current, expression)
		end

		def text
			Expression.new(:text, current)
		end

		def css(selector)
			Expression.new(:css, current, Literal.new(selector))
		end

		def function(name, *arguments)
			Expression.new(:function, name, *arguments)
		end

		def method(name, *arguments)
			if name!=:not
				Expression.new(:function, name, current, *arguments)
			else
				Expression.new(:function, name, *arguments)
			end
		end

		def where(expression)
			if expression
				Expression.new(:where, current, expression)
			else
				current
			end
		end
		#alias_method :[], :where

		def is(expression)
			Expression.new(:is, current, expression)
		end

		def binary_operator(name, rhs)
			Expression.new(:binary_operator, name, current, rhs)
		end

		def union(*expressions)
			Union.new(*[self, expressions].flatten)
		end
		alias_method :+, :union

		def last
			function(:last)
		end

		def position
			function(:position)
		end

		METHODS = [
			# node set
			:count, :id, :local_name, :namespace_uri,
			# string
			:string, :concat, :starts_with, :contains, :substring_before,
			:substring_after, :substring, :string_length, :normalize_space,
			:translate,
			# boolean
			:boolean, :not, :true, :false, :lang,
			# number
			:number, :sum, :floor, :ceiling, :round
		].freeze

		METHODS.each do |key|
			name = key.to_s.tr('_', '-').to_sym
			define_method key do |*args|
				method(name, *args)
			end
		end

		def qname
			method(:name)
		end

		alias_method :inverse, :not
		alias_method :~, :not
		alias_method :!, :not
		alias_method :normalize, :normalize_space
		alias_method :n, :normalize_space

		OPERATORS = [
			%i[equals = ==],
			%i[or or |],
			%i[and and &],
			%i[not_equals != !=],
			%i[lte <= <=],
			%i[lt < <],
			%i[gte >= >=],
			%i[gt > >],
			%i[plus +],
			%i[minus -],
			%i[multiply * *],
			%i[divide div /],
			%i[mod mod %]
		].freeze

		OPERATORS.each do |(name, operator, alias_name)|
			define_method name do |rhs|
				binary_operator(operator, rhs)
			end
			alias_method alias_name, name if alias_name
		end

		AXES = %i[
			ancestor ancestor_or_self attribute descendant_or_self
			following following_sibling namespace parent preceding
			preceding_sibling self
		].freeze

		AXES.each do |key|
			name = key.to_s.tr('_', '-').to_sym
			define_method key do |*element_names|
				axis(name, *element_names)
			end
		end

		alias_method :self_axis, :self

		def ends_with(suffix)
			function(:substring, current, function(:'string-length', current).minus(function(:'string-length', suffix)).plus(1)) == suffix
		end

		def contains_word(word)
			function(:concat, ' ', current.normalize_space, ' ').contains(" #{word} ")
		end

		UPPERCASE_LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞŸŽŠŒ'
		LOWERCASE_LETTERS = 'abcdefghijklmnopqrstuvwxyzàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿžšœ'

		def lowercase
			method(:translate, UPPERCASE_LETTERS, LOWERCASE_LETTERS)
		end

		def uppercase
			method(:translate, LOWERCASE_LETTERS, UPPERCASE_LETTERS)
		end

		def one_of(*expressions)
			expressions.map { |e| current.equals(e) }.reduce(:or)
		end

		def next_sibling(*expressions)
			axis(:'following-sibling')[1].axis(:self, *expressions)
		end

		def previous_sibling(*expressions)
			axis(:'preceding-sibling')[1].axis(:self, *expressions)
		end
	end

	extend PaloAlto::DSL
	include PaloAlto::DSL

	def self.generate
		yield(self)
	end

	class Union
		include Enumerable

		attr_reader :expressions
		alias_method :arguments, :expressions

		def initialize(*expressions)
			@expressions = expressions
		end

		def expression
			:union
		end

		def each(&block)
			arguments.each(&block)
		end

		def method_missing(*args) # rubocop:disable Style/MethodMissingSuper, Style/MissingRespondToMissing
			PaloAlto::Union.new(*arguments.map { |e| e.send(*args) })
		end

		def to_xpath(type = nil)
			Renderer.render(self, type)
		end
	end

	class Literal
		attr_reader :value
		def initialize(value)
			@value = value
		end
	end
	class Renderer
		def self.render(node, type)
			new(type).render(node)
		end

		def initialize(type)
			@type = type
		end

		def render(node)
			arguments = node.arguments.map { |argument| convert_argument(argument) }
			send(node.expression, *arguments)
		end

		def convert_argument(argument)
			case argument
			when Expression, Union then render(argument)
			when Array then argument.map { |element| convert_argument(element) }
			when String then string_literal(argument)
			when Literal then argument.value
			else argument.to_s
			end
		end

		def string_literal(string)
			if string.include?("'")
				string = string.split("'", -1).map do |substr|
					"'#{substr}'"
				end.join(%q(,"'",))
				"concat(#{string})"
			else
				"'#{string}'"
			end
		end

		def this_node
			'.'
		end

		def binary_operator(name, left, right)
			"#{left}#{name}#{right}".gsub('./@', '@')
		end

		def root(current, element_names)
			element_names.any? ? "/#{element_names.join('/')}" : ''
		end

		def relative(current, element_names)
			'.'
		end

		def descendant(current, element_names)
			with_element_conditions("#{current}//", element_names)
		end

		def child(current, element_names)
			with_element_conditions("#{current}/", element_names)
		end

		def axis(current, name, element_names)
			with_element_conditions("#{current}/#{name}::", element_names)
		end

		def anywhere(element_names)
			with_element_conditions('//', element_names)
		end

		def where(on, condition)
			"#{on}[#{condition}]"
		end

		def attribute(current, name)
			if valid_xml_name?(name)
				"#{current}/@#{name}"
			else
				"#{current}/attribute::*[local-name(.) = #{string_literal(name)}]"
			end
		end

		def is(one, two)
			if @type == :exact
				binary_operator('=', one, two)
			else
				function(:contains, one, two)
			end
		end

		def variable(name)
			"%{#{name}}"
		end

		def text(current)
			"#{current}/text()"
		end

		def literal(node)
			node
		end

		def css(current, selector)
			paths = Nokogiri::CSS.xpath_for(selector).map do |xpath_selector|
				"#{current}#{xpath_selector}"
			end
			union(paths)
		end

		def union(*expressions)
			expressions.join(' | ')
		end

		def function(name, *arguments)
			"#{name}(#{arguments.join(', ')})"
		end

	private

		def with_element_conditions(expression, element_names)
			if element_names.length == 1
				"#{expression}#{element_names.first}"
			elsif element_names.length > 1
				"#{expression}*[#{element_names.map { |e| "self::#{e}" }.join(' | ')}]"
			else
				"#{expression}*"
			end
		end

		def valid_xml_name?(name)
			name =~ /^[a-zA-Z_:][a-zA-Z0-9_:\.\-]*$/
		end
	end
	class Expression
		include PaloAlto::DSL

		attr_accessor :expression, :arguments
		def initialize(expression, *arguments)
			@expression = expression
			@arguments = arguments
		end

		def current
			self
		end

		def to_xpath(type = nil)
			Renderer.render(self, type)
		end
	end


	class XML
		class ConfigClass < Expression
			attr_reader :api_attributes, :subclasses
			attr_accessor :parent_instance

			def initialize(parent_instance:, create_children: false)
				@parent_instance = parent_instance
				@subclasses = {}
				@values = {}
				@create_children = create_children
				@external_values = {} # data we received and don't need to set again
				@api_attributes={}

				@expression = :child
				unless self.is_a?(ArrayConfigClass) # for ArrayConfigClass, it will be set externally after the constructor
					xpath_argument = @parent_instance
					@arguments = [ xpath_argument, [_section] ]
				end
			end

			class << self
				attr_accessor :props
			end

			def create!
				@create_children = true
				self
			end

			attr_reader :parent_instance
			attr_accessor :force_relative

			def inspect
				self.to_s[0..-1] + ' ' + self.values(full_tree: false).map{|k,v| "#{k}: #{v.inspect}"}.join(", ") + ">"
			end

			def get_all
				raise(InvalidCommandException, "please use 'get' here") if self.class.superclass != ArrayConfigClass
				payload = {
					type:		"config",
					action: "get",
					xpath:	self.to_xpath
				}

				data = XML.execute(payload)
				start_time=Time.now
				result = self.parent_instance.dup.create!.clear!.external_set(data.xpath('//response/result').first)
				if XML.debug.include?(:statistics)
					puts "Elapsed for parsing #{result.length} results: #{Time.now-start_time} seconds"
				end
				result
			end

			def clear!
				@subclasses = {}
				@values = {}
				self
			end

			def get(ignore_empty_result: false, xpath: self.to_xpath)
				if self.class.superclass == ArrayConfigClass && !@selector
					raise(InvalidCommandException, "Please use 'get_all' here")
				end

				payload = {
					type:		'config',
					action: 'get',
					xpath:	xpath
				}

				data = XML.execute(payload)
				start_time=Time.now

				if data.xpath('//response/result/*').length != 1
					if ignore_empty_result==false
						raise(ObjectNotPresentException, "empty result: #{payload.inspect}")
					end
				else
					#self.parent_instance.dup.create!.clear!.external_set(data.xpath('//response/result').first).first
					@create_children=true
					n = data.xpath('//response/result/*')

					clear!
					external_set(n.first)

					if is_a?(ArrayConfigClass)
						primary_key = get_primary_key(n.first.attribute_nodes, self.class.props)
						set_array_class_attributes(n.first, primary_key) # primary key, api_attributes
					end
				end
				if XML.debug.include?(:statistics)
					puts "Elapsed for parsing: #{Time.now-start_time} seconds"
				end
				self
			end

			def get_primary_key(attribute_nodes, props)
				primary_key_attr = attribute_nodes.find{|attr|
					props.keys.find{|k| k=="@#{attr.name}"}
				}
				Hash[primary_key_attr.name.to_sym, primary_key_attr.value]
			end

			def set_array_class_attributes(child, primary_key)
				@external_values.merge!({ '@' + primary_key.keys.first.to_s => primary_key.values.first})

				#  save also the other attributes like loc and uuid, if set
				child.attribute_nodes.each{|attr|
					next if attr.name.to_sym == primary_key.keys.first
					api_attributes[attr.name] = attr.value
				}
			end

			def external_set(data)
				data.element_children.map{|child|
					child.name.match(/\A[a-zA-Z0-9_-]*\z/) or raise 'invalid character'
					if prop = self.class.props[child.name]
						if has_multiple_values?
							@external_values[child.name]||=[]
							@external_values[child.name] << enforce_type(prop, child.text)
						else
							@external_values[child.name] = enforce_type(prop, child.text)
						end

					elsif new_class=eval('self.class::' + child.name.capitalize.gsub(/-(.)/) {|e| $1.upcase}) rescue false # check for class name in camelcase format
						if new_class.superclass == ConfigClass
							subclass = self.send(child.name.gsub('-','_'))
						elsif new_class.superclass == ArrayConfigClass
							primary_key = get_primary_key(child.attribute_nodes, new_class.props)

							subclass = self.send(child.name, primary_key) # create subclass

							subclass.set_array_class_attributes(child, primary_key) # primary key, api_attributes
						else
							raise
						end
						subclass.external_set(child)
					else
						raise "unknown key: #{child.name}"
					end
					subclass
				}
			end

			def enforce_type(prop_arr, value, value_type: prop_arr['type'])
				case value_type
					when 'bool'
						return true if ['yes', true].include?(value)
						return false if ['no', false].include?(value)
						raise ArgumentError, 'Not bool: ' + value.inspect
					when 'string', 'ipdiscontmask', 'iprangespec', 'ipspec', 'rangelistspec'
						raise(ArgumentError, 'Not string') unless value.is_a?(String)
						if prop_arr['regex']
							raise ArgumentError, "Not matching regex: #{value.inspect} (#{prop_arr["regex"].inspect})" unless value.match(prop_arr["regex"])
						end
						if prop_arr['maxlen']
							raise ArgumentError, 'Too long' if value.length > prop_arr['maxlen'].to_i
						end
						return value
					when 'enum'
						accepted_values = prop_arr.is_a?(Hash) ? prop_arr['enum'].map{|x| x['value']} : prop_arr.map{|x| x['value']} # is an array if part of value_type 'multiple'
						return value if accepted_values.include?(value)
						raise ArgumentError, "not allowed: #{value.inspect} (not within #{accepted_values.inspect})"
					when 'float'
						return Float(value)
					when 'rangedint'
						number = Integer(value)
						return number if number >= prop_arr['min'].to_i && number <= prop_arr['max'].to_i
						raise ArgumentError, "not in range #{prop_arr['min']}..#{prop_arr['max']}: #{number}"
					when 'multiple'
						prop_arr['multi-types'].keys.each{|key|
							return enforce_type(prop_arr['multi-types'][key], value, value_type: key) rescue false
						}
						raise(ArgumentError, "Nothing matching found for #{value.inspect} (#{prop_arr.inspect})")
				end
			end

			def xml_builder(xml, full_tree: false, changed_only: true)
				keys = changed_only ? @values.keys : self.class.props.keys

				keys.map{|k|
					next if k.start_with?('@')
					v=prop_get(k, include_defaults: false)
					next unless v
					Array(v).each{|val|
						val='yes' if val==true
						val='no' if val==false
						xml.method_missing(k, val) # somehow .send does not work with k==:system
					}
				}
				if full_tree
					@subclasses.each{|k,subclass|
						if subclass.is_a?(Hash)
							subclass.each{|k2, subclass2|
								xml.send(k, k2){|xml|
									subclass2.xml_builder(xml, full_tree: full_tree, changed_only: changed_only)
								}
							}
						else
							xml.method_missing(k){|xml| # somehow .send does not work with k==:system
								subclass.xml_builder(xml, full_tree: full_tree, changed_only: changed_only)
							}
						end
					}
				end
				return xml
			end

			def array_class_setter(*args, klass:, section:, &block)
				# either we have a selector or a block
				raise(ArgumentError, "wrong number of arguments (expected one argument or block)") unless (args.length==1 && !block) || (args.empty? && block)

				entry = klass.new(parent_instance: self, create_children: @create_children)
				if block
					obj = self.child(section.to_sym).where(PaloAlto.instance_eval(&block))
					entry.expression = obj.expression
					entry.arguments = obj.arguments
					entry
				else
					selector=args[0]
					@subclasses[section]||= {}

					entry.instance_variable_get('@external_values').merge!({"@#{selector.keys.first}" => selector.values.first})
					entry.selector = selector
					entry.set_xpath_from_selector

					if @create_children
						@subclasses[section][selector] ||= entry
					else
						entry
					end
				end
			end

			def values(full_tree: true, include_defaults: true)
				h={}
				self.class.props.keys.map{|k|
					prop = prop_get(k, include_defaults: include_defaults)
					h[k] = prop if prop
				}
				if full_tree
					@subclasses.each{|k,subclass|
						if subclass.is_a?(Hash)
							h[k]||={}
							subclass.each{|k2, subclass2|
								h[k][k2]=subclass2.values(full_tree: true, include_defaults: include_defaults)
							}
						else
							h[k]=subclass.values(full_tree: true, include_defaults: include_defaults)
						end
					}
				end
				return h
			end

			def set_values(h, external: false)
				if h.is_a?(PaloAlto::XML::ConfigClass)
					h=h.values(include_defaults: false)
				end
				raise(ArgumentError, 'needs to be a Hash') unless h.is_a?(Hash)
				clear!
				create!
				h.each{|k,v|
					if v.is_a?(Hash)
						self.send(k.to_s.gsub('-','_')).set_values(v, external: external)
					else
						if external
							@external_values[k]=v
						else
							self.prop_set(k,v)
						end
					end
				}
				self
			end

			def prop_get(prop, include_defaults: true)
				my_prop = self.class.props[prop]
				if @values.has_key?(prop)
					return @values[prop]
				elsif @external_values.has_key?(prop) && @external_values[prop].is_a?(Array)
					return @values[prop] = @external_values[prop].dup
				elsif @external_values.has_key?(prop)
					return @external_values[prop]
				elsif my_prop.has_key?("default") && include_defaults
					return enforce_type(my_prop, my_prop['default'])
				else
					return nil
				end
			end

			def prop_set(prop, value)
				my_prop = self.class.props[prop] or raise(InternalErrorException, "Unknown attribute for #{self.class}: #{prop}")

				if has_multiple_values? && value.is_a?(String)
					value = value.split(/\s+/)
				end

				if value.is_a?(Array)
					@values[prop] = value.map{|v| enforce_type(my_prop, v)}
				elsif value.nil?
					@values[prop] = nil
				else
					@values[prop] = enforce_type(my_prop, value)
				end
			end

			def to_xml(changed_only:, full_tree:, include_root: )
				builder = Nokogiri::XML::Builder.new{|xml|
					xml.send(self._section, (self.selector rescue nil)) {
						self.xml_builder(xml, changed_only: changed_only, full_tree: full_tree)
					}
				}
				if include_root
					builder.doc.root.to_xml
				else
					builder.doc.root.children.map(&:to_xml).join("\n")
				end
			end

			def push!
				xml_str = self.to_xml(changed_only: false, full_tree: true, include_root: true)

				payload = {
					type:		'config',
					action: 'edit',
					xpath:	self.to_xpath,
					element: xml_str
				}
				XML.execute(payload)
			end

			def delete_child(name)
				@subclasses.delete(name) && true || false
			end

			def delete!
				payload = {
					type:		'config',
					action: 'delete',
					xpath:	self.to_xpath
				}
				XML.execute(payload)
			end

			def multimove!(dst:, members:, all_errors: false)
				source = self.to_xpath

				builder = Nokogiri::XML::Builder.new{|xml|
					xml.root {
						xml.send('selected-list') {
							xml.source(xpath: source) {
								members.each{|member| xml.member member}
							}
						}
						xml.send('all-errors', all_errors ? 'yes' : 'no')
					}
				}

				element = builder.doc.root.children.map(&:to_xml).join("\n")

				payload = {
					type:		'config',
					action: 'multi-move',
					xpath:	dst,
					element: element
				}

				XML.execute(payload)
			end
		end

		class ArrayConfigClass < ConfigClass
			attr_accessor :selector

			def move!(where:, dst: nil)
				payload = {
					type:		'config',
					action: 'move',
					xpath:	self.to_xpath,
					where: where
				}
				if dst
					payload[:dst] = dst
				end

				XML.execute(payload)
			end

			def set_xpath_from_selector(selector: @selector)
				xpath = self.parent_instance.child(_section)
				k,v=selector.first
				obj = xpath.where(PaloAlto.xpath_attr(k.to_sym) == v)

				@expression = obj.expression
				@arguments = obj.arguments
			end

			def rename!(new_name)
				# https://docs.paloaltonetworks.com/pan-os/10-1/pan-os-panorama-api/pan-os-xml-api-request-types/configuration-api/rename-configuration.html
				payload = {
					type:		'config',
					action: 'rename',
					xpath:	self.to_xpath,
					newname: new_name
				}

				result = XML.execute(payload)

				# now update also the internal value to the new name
				self.selector.transform_values!{new_name}
				@external_values["@#{self.selector.keys.first}"] = new_name
				set_xpath_from_selector()
			end
		end

	#no end of class Xml here as generated source will be added here
