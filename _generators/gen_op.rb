require "nokogiri"
require "pp"

xml = Nokogiri::XML.parse(File.read('schema/cms-opschema.xml')).xpath("union[@name='operations']") ; nil

def iterate(xml)
  xml.children.inject({}){|hash, xml_child|
    if xml_child.is_a?(Nokogiri::XML::Element)
      attributes = xml_child.attributes.inject({}){|hash, attr| hash[attr.first] = attr.last.value; hash}
      if xml_child.name == 'choice'
        ret = iterate(xml_child)
        hash.merge!(ret)
      elsif xml_child.name == 'element'
        #hash[xml_child.attr("name")]=iterate(xml_child)
        # TODO: check if type is "enum", if yes, collect available values
        hash[xml_child.attr("name")]={}
        hash[xml_child.attr("name")][:obj] = xml_child.name.to_sym
        hash[xml_child.attr("name")][:attributes] = attributes
      else
        hash[xml_child.attr("name")]=iterate(xml_child)
        hash[xml_child.attr("name")][:obj] = xml_child.name.to_sym
        hash[xml_child.attr("name")][:attributes] = attributes
      end
    end
    hash
  }
end

hash=iterate(xml)

header=File.read("gen_op.template.rb")
footer=<<EOF
    end
  end
end
EOF

File.open("#{__dir__}/../lib/palo_alto/op.rb","w"){|f|
  f.write( header + "@@ops=" + hash.pretty_inspect + footer)
}
