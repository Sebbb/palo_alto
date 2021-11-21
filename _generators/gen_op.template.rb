# frozen_string_literal: true

require 'nokogiri'

module PaloAlto
  class XML
    def op
      Op.new
    end

    class Op
      def execute(cmd, type: nil, location: nil, additional_payload: {})
        payload = build_payload(cmd).merge(additional_payload)

        if type == 'tpl'
          run_with_template_scope(location) { XML.execute(payload) }
        elsif type == 'dg'
          XML.execute(payload.merge({ vsys: location }))
        elsif !type || type == 'shared'
          XML.execute(payload)
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

      def xml_builder(xml, ops, obj)
        case obj
        when String
          section = obj
          data = nil
        when Hash
          section = obj.keys.first
          data = obj[section]
        else
          raise obj.pretty_inspect
        end

        unless ops.key?(section.to_s)
          err = "Error #{section} does not exist. Valid: " + ops.keys.pretty_inspect
          raise err
        end

        ops_tree = ops[section.to_s]

        section = escape_xpath_tag(section)

        case ops_tree[:obj]
        when :element
          xml.public_send(section, data)
        when :array
          xml.public_send(section) do
            data.each do |el|
              key = ops_tree.keys.first
              xml.public_send(escape_xpath_tag(key), el)
            end
          end
        when :sequence
          if data.nil?
            xml.send(section)
          elsif data.is_a?(Hash)
            xml.send(section)  do
              xml_builder(xml, ops_tree, data)
            end
          else # array

            if data.is_a?(Array)
              attr = data.find { |child| child.is_a?(Hash) && ops_tree[child.keys.first.to_s][:obj] == :'attr-req' }
              data.delete(attr)
            else
              attr = {}
            end

            xml.public_send(section, attr) do
              data.each do |child|
                xml_builder(xml, ops_tree, child)
              end
            end
          end
        when :union
          k, v = obj.first
          xml.send("#{k}_")  do
            xml_builder(xml, ops_tree, v)
          end
        else
          raise ops_tree[:obj].pretty_inspect
        end
        xml
      end

      def to_xml(obj)
        builder = Nokogiri::XML::Builder.new do |xml|
          xml_builder(xml, @@ops, obj)
        end
        builder.doc.root.to_xml
      end
