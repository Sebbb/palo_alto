# rubocop:disable Style/FrozenStringLiteralComment
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
      if name != :not
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
    # alias_method :[], :where

    def is(expression)
      Expression.new(:is, current, expression)
    end

    def binary_operator(name, rhs)
      Expression.new(:binary_operator, name, current, rhs)
    end

    def union(*expressions)
      Union.new(*[self, expressions].flatten)
    end
    alias + union

    def last
      function(:last)
    end

    def position
      function(:position)
    end

    # rubocop:disable Lint/BooleanSymbol
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
    # rubocop:enable Lint/BooleanSymbol

    METHODS.each do |key|
      name = key.to_s.tr('_', '-').to_sym
      define_method key do |*args|
        method(name, *args)
      end
    end

    def qname
      method(:name)
    end

    alias inverse not
    alias ~ not
    alias ! not
    alias normalize normalize_space
    alias n normalize_space

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

    alias self_axis self

    def ends_with(suffix)
      function(:substring, current,
               function(:'string-length', current).minus(function(:'string-length', suffix)).plus(1)) == suffix
    end

    def contains_word(word)
      function(:concat, ' ', current.normalize_space, ' ').contains(" #{word} ")
    end

    UPPERCASE_LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞŸŽŠŒ'.freeze
    LOWERCASE_LETTERS = 'abcdefghijklmnopqrstuvwxyzàáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿžšœ'.freeze

    def lowercase
      method(:translate, UPPERCASE_LETTERS, LOWERCASE_LETTERS)
    end

    def parenthesis(arg)
      Expression.new(:parenthesis, arg)
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
    alias arguments expressions

    def initialize(*expressions)
      @expressions = expressions
    end

    def expression
      :union
    end

    def each(&block)
      arguments.each(&block)
    end

    def method_missing(*args) # rubocop:disable Style/MissingRespondToMissing
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

    def parenthesis(arg)
      "(#{arg})"
    end

    def root(_current, element_names)
      element_names.any? ? "/#{element_names.join('/')}" : ''
    end

    def relative(_current, _element_names)
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
      name =~ /^[a-zA-Z_:][a-zA-Z0-9_:.\-]*$/
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
      attr_reader :api_attributes, :subclasses, :parent_instance
      alias :_class :class

      def initialize(parent_instance:, client:, create_children: false)
        @client = client
        @parent_instance = parent_instance
        @subclasses = {}
        @values = {}
        @create_children = create_children
        @external_values = {} # data we received and don't need to set again
        @api_attributes = {}

        @expression = :child
        unless is_a?(ArrayConfigClass) # for ArrayConfigClass, it will be set externally after the constructor
          xpath_argument = @parent_instance
          @arguments = [xpath_argument, [_section]]
        end
      end

      def maybe_register_subclass(name, instance)
        return instance unless instance_variable_get('@create_children')

        @subclasses[name] ||= instance
      end

      def selector_subclasses
        []
      end

      class << self
        attr_accessor :props
      end

      def create!
        @create_children = true
        self
      end

      def inspect
        to_s[0...-1] + ' ' + values(full_tree: false).map { |k, v| "#{k}: #{v.inspect}" }.join(', ') + '>'
      end

      def get_all(xpath: to_xpath)
        raise(InvalidCommandException, "please use 'get' here") if self._class.superclass != ArrayConfigClass

        payload = {
          type: 'config',
          action: 'get',
          xpath: xpath
        }

        data = @client.execute(payload)
        start_time = Time.now
        result = parent_instance.dup.create!.clear!.external_set(data.xpath('//response/result').first)
        if @client.debug.include?(:statistics)
          warn "Elapsed for parsing #{result.length} results: #{Time.now - start_time} seconds"
        end
        result
      end

      def clear!
        @subclasses = {}
        @values = {}
        self
      end

      def complete(xpath:)
        payload = {
          type: 'config',
          action: 'complete',
          xpath: xpath
        }

        @client.execute(payload)
      end

      def get(ignore_empty_result: false, xpath: to_xpath, return_only: false)
        if self._class.superclass == ArrayConfigClass && !@selector
          raise(InvalidCommandException, "Please use 'get_all' here")
        end

        payload = {
          type: 'config',
          action: 'get',
          xpath: xpath
        }

        data = @client.execute(payload)
        start_time = Time.now

        if data.xpath('//response/result/*').length != 1 && (ignore_empty_result == false)
          raise(ObjectNotPresentException, "empty result: #{payload.inspect}")
        end

        if return_only
          data.xpath('//response/result/*')
        else
          @create_children = true
          n = data.xpath('//response/result/*')
          if n.any?
            clear!
            external_set(n.first)

            if is_a?(ArrayConfigClass)
              primary_key = get_primary_key(n.first.attribute_nodes, self._class.props)
              set_array_class_attributes(n.first, primary_key) # primary key, api_attributes
            end
          end
          self
        end.tap do
          warn "Elapsed for parsing: #{Time.now - start_time} seconds" if @client.debug.include?(:statistics)
        end
      end

      def get_primary_key(attribute_nodes, props)
        primary_key_attr = attribute_nodes.find do |attr|
          props.keys.find { |k| k == "@#{attr.name}" }
        end
        Hash[primary_key_attr.name.to_sym, primary_key_attr.value]
      end

      def set_array_class_attributes(child, primary_key)
        @external_values.merge!({ "@#{primary_key.keys.first}" => primary_key.values.first })

        #  save also the other attributes like loc and uuid, if set
        child.attribute_nodes.each do |attr|
          next if attr.name.to_sym == primary_key.keys.first

          api_attributes[attr.name] = attr.value
        end
      end

      def get_class_from_child_str(child)
        str = child.name.dup
        str[0] = 'K' if str == 'class'
        str[0] = str[0].upcase
        name = str.gsub(/-(.)/) { |_e| Regexp.last_match(1).upcase }
        self._class.const_get(name)
      rescue NameError
        raise "Child not found for #{self._class.to_s}: #{child.name}"
      end

      def external_set(data)
        data.element_children.map do |child|
          child.name.match(/\A[a-zA-Z0-9_-]*\z/) or raise 'invalid character'
          if (prop = self._class.props[child.name])
            if has_multiple_values?
              @external_values[child.name] ||= []
              @external_values[child.name] << enforce_type(prop, child.text, skip_validation: true)
            else
              @external_values[child.name] = enforce_type(prop, child.text, skip_validation: true)
            end

          elsif (new_class = get_class_from_child_str(child))
            if new_class.superclass == ConfigClass
              subclass = send(child.name.gsub('-', '_'))
            elsif new_class.superclass == ArrayConfigClass
              primary_key = get_primary_key(child.attribute_nodes, new_class.props)

              subclass = send(child.name, primary_key) # create subclass

              subclass.set_array_class_attributes(child, primary_key) # primary key, api_attributes
            else
              raise
            end
            subclass.external_set(child)
          else
            raise "unknown key: #{child.name}"
          end
          subclass
        end
      end

      def enforce_type(prop_hash, value, value_type: prop_hash['type'], skip_validation: false)
        if prop_hash.is_a?(Hash) && prop_hash['ui-field-hint'] == 'type: "bool"'
          value_type = 'bool'
        end
        case value_type
        when 'bool'
          return true if ['yes', true].include?(value)
          return false if ['no', false].include?(value)

          raise ArgumentError, "Not bool: #{value.inspect}"
        when 'string', 'ipdiscontmask', 'iprangespec', 'ipspec', 'rangelistspec'
          raise(ArgumentError, "Not string: #{value.inspect}") unless value.is_a?(String)

          if prop_hash['regex'] && !value.match(prop_hash['regex']) && !value.match(prop_hash['regex'])
            raise ArgumentError,
                  "#{self._class} - Not matching regex: #{value.inspect} (#{prop_hash['regex'].inspect})" unless skip_validation
          end
          if prop_hash['maxlen'] && (value.length > prop_hash['maxlen'].to_i)
            raise(ArgumentError, "Too long, max. #{prop_hash['maxlen'].to_i} characters allowed") unless skip_validation
          end

          value
        when 'enum'
          accepted_values = if prop_hash.is_a?(Hash)
                              prop_hash['enum'].map { |x| x['value'] }
                            else
                              prop_hash.map { |x| x['value'] } # is an array if part of value_type 'multiple'
                            end
          return value if accepted_values.include?(value)

          raise ArgumentError, "not allowed: #{value.inspect} (not within #{accepted_values.inspect})"
        when 'float'
          Float(value)
        when 'rangedint'
          number = Integer(value)
          return number if number >= prop_hash['min'].to_i && number <= prop_hash['max'].to_i

          raise ArgumentError, "not in range #{prop_hash['min']}..#{prop_hash['max']}: #{number}"
        when 'multiple'
          prop_hash['multi-types'].each_key do |key|
            # TODO: prop_hash['multi-types'][key] might be an Array, handle that better and provide the correct format to enforce_type
            return enforce_type(prop_hash['multi-types'][key], value, value_type: key)
          rescue StandardError
            false
          end
          raise(ArgumentError, "Nothing matching found for #{value.inspect} (#{prop_hash.inspect})")
        end
      end

      def xml_builder(xml, full_tree: false, tag_filter: nil)
        self._class.props.keys.select { |key| tag_filter.nil? || tag_filter.include?(key) }.map do |k|
          next if k.start_with?('@')

          v = prop_get(k, include_defaults: false)
          next if v.nil?

          Array(v).each do |val|
            val = 'yes' if val == true
            val = 'no' if val == false
            xml.method_missing(k, val) # somehow .send does not work with k==:system
          end
        end
        if full_tree
          @subclasses.each do |tag_name, subclass|
            next if tag_filter && !tag_filter.include?(tag_name)

            if subclass.is_a?(Hash)
              subclass.each do |k2, subclass2|
                tag_attr = k2.merge(subclass2.api_attributes.select { |attr, _| %w(uuid).include?(attr)})
                # put received uuid into XML
                xml.public_send(tag_name, tag_attr) do |xml2|
                  subclass2.xml_builder(xml2, full_tree: full_tree)
                end
              end
            else
              tag_name = 'method_' if tag_name=='method'
              xml.public_send(tag_name) do |xml2|
                subclass.xml_builder(xml2, full_tree: full_tree)
              end
            end
          end
        end
        xml
      end

      # used for Array classes (e.g. 'entry')
      def array_class_setter(*args, klass:, section:, &block)
        # either we have a selector or a block
        unless (args.length == 1 && !block) || (args.empty? && block)
          raise(ArgumentError,
                'wrong number of arguments (expected one argument or block)')
        end

        entry = klass.new(parent_instance: self, client: @client, create_children: @create_children)

        if block
          expression = PaloAlto.instance_eval(&block)
          raise(ArgumentError, 'Block is not an expression!') unless expression.is_a?(PaloAlto::Expression) || expression.nil?

          obj = child(section.to_sym).where(expression)
          entry.expression = obj.expression
          entry.arguments = obj.arguments
          entry
        else
          selector = args[0]
          @subclasses[section] ||= {}

          selector_key = "@#{selector.keys.first}"
          prop = klass.props[selector_key] or raise(ArgumentError, 'Selector does not exist')

          selector_value = enforce_type(prop, selector.values.first)

          entry.instance_variable_get('@external_values').merge!({ selector_key => selector_value })
          entry.selector = selector
          entry.set_xpath_from_selector!

          if @create_children
            @subclasses[section][selector] ||= entry
          else
            entry
          end
        end
      end

      def values(full_tree: true, include_defaults: true)
        h = {}
        self._class.props.keys.map do |k|
          prop = prop_get(k, include_defaults: include_defaults)
          h[k] = prop if prop
        end
        if full_tree
          @subclasses.each do |k, subclass|
            if subclass.is_a?(Hash)
              h[k] ||= {}
              subclass.each do |k2, subclass2|
                h[k][k2] = subclass2.values(full_tree: true, include_defaults: include_defaults)
              end
            else
              h[k] = subclass.values(full_tree: true, include_defaults: include_defaults)
            end
          end
        end
        h
      end

      def set_values(h, external: false)
        h = h.values(include_defaults: false) if h.is_a?(PaloAlto::XML::ConfigClass)
        raise(ArgumentError, 'needs to be a Hash') unless h.is_a?(Hash)

        clear!
        create!
        h.each do |k, v|
          if v.is_a?(Hash)
            if selector_subclasses.include?(k.to_s.gsub('-', '_'))
              v.each do |selector, content|
                send(k.to_s.gsub('-', '_'), selector).set_values(content, external: external)
              end
            else
              send(k.to_s.gsub('-', '_')).set_values(v, external: external)
            end
          elsif external
            @external_values[k] = v
          else
            prop_set(k, v)
          end
        end
        self
      end

      def prop_get(prop, include_defaults: true)
        my_prop = self._class.props[prop]
        if @values.key?(prop)
          @values[prop]
        elsif @external_values.key?(prop) && @external_values[prop].is_a?(Array)
          @values[prop] = @external_values[prop].dup
        elsif @external_values.key?(prop)
          @external_values[prop]
        elsif my_prop.key?('default') && ( my_prop['optional'] != 'yes' || include_defaults )
          enforce_types(my_prop, my_prop['default'])
        end
      end

      def enforce_types(prop_hash, values)
        return if values.nil?

        values = values.split(/\s+/) if has_multiple_values? && values.is_a?(String)

        if values.is_a?(Array) && has_multiple_values?
          values.map { |v| enforce_type(prop_hash, v) }
        elsif !has_multiple_values?
          enforce_type(prop_hash, values)
        else
          raise(ArgumentError, 'Needs to be Array but is not, or vice versa')
        end
      end

      def prop_set(prop, value)
        my_prop = self._class.props[prop] or raise(InternalErrorException,
                                                  "Unknown attribute for #{self._class}: #{prop}")

        @values[prop] = enforce_types(my_prop, value)
      end

      def to_xml(tag_filter: nil, full_tree:, include_root:)
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.public_send(_section, begin
            selector
          rescue StandardError
            nil
          end) do
            xml_builder(xml, full_tree: full_tree, tag_filter: tag_filter)
          end
        end
        if include_root
          builder.doc.root.to_xml
        else
          builder.doc.root.children.map(&:to_xml).join("\n")
        end
      end

      def edit!
        xml_str = to_xml(full_tree: true, include_root: true)

        payload = {
          type: 'config',
          action: 'edit',
          xpath: to_xpath,
          element: xml_str
        }
        @client.execute(payload)
      rescue PaloAlto::ConnectionErrorException => e
        warn "*** edit! failed (#{e.inspect}), validating against running configuration"
        validate_object = dup
        validate_object.clear!
        validate_object.get
        raise e unless validate_object.values == values
        warn '*** validation successful'
      end

      alias :push! :edit!

      def set!(tag_filter: nil) # TODO: make fields to push selectable
        xml_str = to_xml(full_tree: true, include_root: false, tag_filter: tag_filter)

        payload = {
          type: 'config',
          action: 'set',
          xpath: to_xpath,
          element: xml_str
        }
        @client.execute(payload)
      end

      def delete_child(name)
        @subclasses.delete(name) && true || false
      end

      def delete!
        payload = {
          type: 'config',
          action: 'delete',
          xpath: to_xpath
        }
        @client.execute(payload)
      end

      def multimove!(dst:, members:, all_errors: false)
        source = to_xpath

        builder = Nokogiri::XML::Builder.new do |xml|
          xml.root do
            xml.public_send('selected-list') do
              xml.source(xpath: source) do
                members.each { |member| xml.member member }
              end
            end
            xml.public_send('all-errors', all_errors ? 'yes' : 'no')
          end
        end

        element = builder.doc.root.children.map(&:to_xml).join("\n")

        payload = {
          type: 'config',
          action: 'multi-move',
          xpath: dst,
          element: element
        }

        @client.execute(payload)
      end
    end

    class ArrayConfigClass < ConfigClass
      attr_accessor :selector

      def move!(where:, dst: nil)
        payload = {
          type: 'config',
          action: 'move',
          xpath: to_xpath,
          where: where
        }
        payload[:dst] = dst if dst

        @client.execute(payload)
      end

      def set_xpath_from_selector!(selector: @selector)
        xpath = parent_instance.child(_section)
        k, v = selector.first
        obj = xpath.where(PaloAlto.xpath_attr(k.to_sym) == v)

        @expression = obj.expression
        @arguments = obj.arguments
      end

      def rename!(new_name, internal_only: false)
        # https://docs.paloaltonetworks.com/pan-os/10-1/pan-os-panorama-api/pan-os-xml-api-request-types/configuration-api/rename-configuration.html
        result = if internal_only
                   true
                 else
                   payload = {
                     type: 'config',
                     action: 'rename',
                     xpath: to_xpath,
                     newname: new_name
                   }

                   @client.execute(payload)
                 end

        # now update also the internal value to the new name
        selector.transform_values! { new_name }
        @external_values["@#{selector.keys.first}"] = new_name
        set_xpath_from_selector!
        result
      end
    end

    # no end of class Xml here as generated source will be added here
