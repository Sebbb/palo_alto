require "nokogiri"
require "pp"

module PaloAlto
  class XML

    def op
      Op.new
    end

    class Op
      def execute(obj, additional_payload = {})

        cmd = to_xml(obj)

        if obj=='commit' || obj.keys.first.to_sym == :commit
          type='commit'
          action='panorama'
        elsif obj=='commit-all' || obj.keys.first.to_sym == :'commit-all'
          type='commit'
          action='all'
        else
          type='op'
          action='panorama'
        end

        payload = {
          type:   type,
          action: action,
          cmd:   cmd
        }.merge(additional_payload)

        XML.execute(payload)
      end

      def escape_xpath_tag(tag)
        if tag.to_s.include?('-') # https://stackoverflow.com/questions/48628259/nokogiri-how-to-name-a-node-comment
          tag
        else
          tag.to_s + "_"
        end
      end

      def xml_builder(xml, ops, obj)
        if obj.is_a?(String)
          section = obj
          data = nil
        elsif obj.is_a?(Hash)
          section = obj.keys.first
          data = obj[section]
        else
          puts "----------"
          pp obj
          raise
        end

        unless ops.has_key?(section.to_s)
          err = "Error #{section.to_s} does not exist. Valid: " + ops.keys.pretty_inspect
          raise err
        end

        ops_tree = ops[section.to_s]
        #pp [:ops, ops_tree]
        #pp [:obj, obj]
        #puts "****************** build #{section} (#{ops_tree[:obj]})"

        section = escape_xpath_tag(section)

        case ops_tree[:obj]
        when :element
          xml.public_send(section, data)
        when :array
          xml.public_send(section) {
            data.each{|el|
              key = ops_tree.keys.first
              xml.public_send(escape_xpath_tag(key), el)
            }
          }
        when :sequence
          if data==nil
            xml.send(section)
          elsif data.is_a?(Hash)
            xml.send(section){
              xml_builder(xml, ops_tree, data)
            }
          else # array

            if data.is_a?(Array)
              attr = data.find { |child| ops_tree[child.keys.first.to_s][:obj]==:'attr-req' }
              data.delete(attr)
            else
              attr = {}
            end

            xml.public_send(section, attr){
              data.each{|child|
                xml_builder(xml, ops_tree, child)
              }
            }
          end
        when :union
          k,v=obj.first
          xml.send("#{k}_"){
            xml_builder(xml, ops_tree, v)
          }
        else
          pp ops_tree[:obj]
          raise
        end
        xml
      end


      def to_xml(obj)
        builder = Nokogiri::XML::Builder.new{|xml|
          xml_builder(xml, @@ops, obj)
        }
        builder.doc.root.to_xml
      end
