# frozen_string_literal: true

require 'nokogiri'
require 'pp'

xml = Nokogiri::XML.parse(File.read('schema/cms-opschema.xml')).xpath("union[@name='operations']")
nil

class String
  alias _inspect inspect
  def inspect
    return _inspect if match(/[\t\n]/)

    "'#{gsub("'", "\\\\'")}'"
  end
end

def iterate(xml)
  xml.children.each_with_object({}) do |xml_child, hash|
    next unless xml_child.is_a?(Nokogiri::XML::Element)

    attributes = xml_child.attributes.each_with_object({}) do |attr, hash|
      hash[attr.first] = attr.last.value
    end
    case xml_child.name
    when 'choice'
      ret = iterate(xml_child)
      hash.merge!(ret)
    when 'element'
      # hash[xml_child.attr('name')] = iterate(xml_child)
      # TODO: check if type is 'enum', if yes, collect available values
      hash[xml_child.attr('name')] = {}
      hash[xml_child.attr('name')][:obj] = xml_child.name.to_sym
      hash[xml_child.attr('name')][:attributes] = attributes
    else
      hash[xml_child.attr('name')] = iterate(xml_child)
      hash[xml_child.attr('name')][:obj] = xml_child.name.to_sym
      hash[xml_child.attr('name')][:attributes] = attributes
    end
  end
end

hash = iterate(xml)

header = File.read('gen_op.template.rb')
footer = <<~EOF
      end
    end
  end
EOF

File.open("#{__dir__}/../lib/palo_alto/op.rb", 'w') do |f|
  f.write("#{header}@@ops=#{hash.pretty_inspect}#{footer}")
end
