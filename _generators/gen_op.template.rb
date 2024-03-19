# frozen_string_literal: true

require 'nokogiri'

module PaloAlto
  class XML
    def op
      @op ||= Op.new(client: self)
    end

    class Op
      def initialize(client:)
        @client = client
      end

      def execute(cmd, type: nil, location: nil, additional_payload: {})
        payload = build_payload(cmd).merge(additional_payload)

        if type == 'tpl'
          run_with_template_scope(location) { @client.execute(payload) }
        elsif type == 'dg'
          @client.execute(payload.merge({ vsys: location }))
        elsif !type || type == 'shared'
          @client.execute(payload)
        else
          raise(ArgumentError, "invalid type: #{type.inspect}")
        end
      end

      def run_with_template_scope(name)
        if block_given?
          run_with_template_scope(name)
          begin
            return yield
          ensure
            run_with_template_scope(nil)
          end
        end

        cmd = if name
                { set: { system: { setting: { target: { template: { name: name } } } } } }
              else
                { set: { system: { setting: { target: 'none' } } } }
              end

        execute(cmd)
      end

      def build_payload(obj)
        cmd = to_xml(obj)

        if obj == 'commit' || obj.keys.first.to_sym == :commit
          type = 'commit'
          action = 'panorama'
        elsif obj == 'commit-all' || obj.keys.first.to_sym == :'commit-all'
          type = 'commit'
          action = 'all'
        else
          type = 'op'
          action = 'panorama'
        end

        {
          type: type,
          action: action,
          cmd: cmd
        }
      end

      def escape_xpath_tag(tag)
        if tag.to_s.include?('-') # https://stackoverflow.com/questions/48628259/nokogiri-how-to-name-a-node-comment
          tag
        else
          "#{tag}_"
        end
      end

      def xml_builder_iter(xml, ops, data)
        raise 'No Ops?!' if ops.nil?

        case data
        when String
          section = data
          data2 = nil
          xml_builder(xml, ops, section, data2)
        when Hash, Array
          data.each do |section, data2|
            xml_builder(xml, ops, section, data2)
          end
        else
          raise data.pretty_inspect
        end
      end

      def xml_builder(xml, ops, section, data, type = ops[section.to_s]&.[](:obj))
        ops_tree = ops[section.to_s] || raise("no ops tree for section #{section}, #{ops.keys.inspect}")
        # pp [:xml_builder, :section, section, :type, type]
        # obj = data

        case type
        when :element
          xml.public_send(escape_xpath_tag(section), data)
        when :array
          xml.public_send(escape_xpath_tag(section)) do
            raise 'data is Hash and should be Array' if data.is_a?(Hash)

            data.each do |el|
              key = ops_tree.keys.first
              case el
              when Hash
                attr = ops_tree[key].find { |_k, v| v.is_a?(Hash) && v[:obj] == :'attr-req' }.first
                xml.public_send(escape_xpath_tag(key), { attr => el[attr.to_sym] }) do
                  remaining_attrs = el.reject { |k, _v| k == attr.to_sym }

                  if remaining_attrs.any?
                    xml_builder(xml, ops_tree[key], remaining_attrs.keys.first.to_s, remaining_attrs.values.first,
                                :array)
                  end
                end
              when String
                xml.public_send(key, el)
              end
            end
          end
        when :sequence
          if data.nil? || data == true
            xml.send(escape_xpath_tag(section))
          elsif data.is_a?(Hash)
            xml.send(escape_xpath_tag(section)) do
              xml_builder_iter(xml, ops_tree, data)
            end
          else # array, what else could it be?!
            raise "Unknown: #{attr.inspect}" unless data.is_a?(Array)

            raise 'Too many hashes in an array, please update' if data.length > 1

            key = ops_tree.keys.first
            attr_name = ops_tree[key].find { |_k, v| v.is_a?(Hash) && v[:obj] == :'attr-req' }.first

            hash = data.first.dup

            data = [hash.reject { |k| k == attr_name.to_sym }]
            attr = { attr_name => hash[attr_name.to_sym] }

            xml.public_send(escape_xpath_tag(section)) do
              xml.public_send(escape_xpath_tag(key), attr) do
                data.each do |child|
                  xml_builder_iter(xml, ops_tree[key], child)
                end
              end
            end
          end
        when :union
          xml.public_send(escape_xpath_tag(section)) do
            xml_builder_iter(xml, ops[section.to_s], data)
          end
        else
          raise ops_tree[:obj].pretty_inspect
        end
        xml
      end

      def to_xml(obj)
        builder = Nokogiri::XML::Builder.new do |xml|
          xml_builder_iter(xml, @@ops, obj)
        end
        builder.doc.root.to_xml
      end
