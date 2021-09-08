require "json"
require "pp"
panorama_json = JSON.parse(File.read("panorama.json"));nil

class String
	def camelcase(first_char: true)
		self.match(/\A[a-zA-Z0-9_-]*\z/) or raise "invalid character"
		str=self.dup
		str[0]=str[0].upcase if first_char
		str.gsub(/-(.)/) {|e| $1.upcase}
	end

	def pluralize
		str=self+'s'
		str.gsub(/ys$/, 'ies').gsub(/ss$/, 'ses')
	end
end

def indent_puts(str, indent:)
	str.split("\n").each{|line|
		$f.puts(("\t" * indent + line).rstrip)
	}
end

def iter(child_key, child, indent:)
	raise 'iter: wrong class' unless child.is_a?(Hash)

	child_classes = []

	props = []	# name, validator

	child_attr=child['@attr']
	if child_attr["node-type"]=='sequence'
		iter_sequence(child_key, child, indent: indent)
		child_classes << child_key

	elsif child_attr["node-type"]=='array'
		child_key = child_key.split("_").first
		iter_array(child_key, child, indent: indent)
		child_classes << child_key
		#pp child_key

	elsif child_attr["node-type"]=='element'
		#STDERR.puts "------------element------------"
		#STDERR.puts [:child_key, child_key].inspect
		#STDERR.puts child.inspect
		#STDERR.puts child_attr.inspect
		props << {child_key => child_attr}
	elsif child_attr["node-type"]=='union'
		#pp child_attr

		child_key = child_key.split("_").first
		iter_array(child_key, child, indent: indent)
		child_classes << child_key
		
		#props << {child_key => child_attr} # TODO: we may need to store this information as well
		#pp props
	elsif child_attr["node-type"]=="attr-req"
		props << {child_key => child_attr}
	elsif child_attr["node-type"]=='choice'
		#STDERR.puts "-------"
		#STDERR.puts child_key
		#STDERR.puts child_attr
		#STDERR.puts child


		child.delete('@attr')
		child.keys.each{|k|
			#STDERR.puts [:k, k, child[k]].inspect
			my_child_classes, my_props = iter(k, child[k], indent: indent)
			props+=my_props
			#STDERR.puts my_child_classes.inspect # TODO: I may need to do something with these as well!
			#pp k
			child_classes << k
			#props << {k => child[k]}
		}
	else
		pp json
		raise "unknown node-type: #{child_attr["node-type"]}"
	end
	#pp props
	#pp child_classes

	return child_classes, props
end

def iter_sequence(section, json, indent:)
	attr = json.delete('@attr')
	raise unless attr["node-type"]=='sequence'

	class_type = json.keys.any?{|k| k.start_with?('@')} ? 'ArrayConfigClass' : 'ConfigClass'

	indent_puts "class #{section.camelcase} < " + class_type, indent: indent

	indent_puts 'def has_multiple_values?', indent: indent+1
	indent_puts 'false', indent: indent+2
	indent_puts 'end', indent: indent+1

	indent_puts("def _section", indent: indent+1)
	indent_puts(":'#{section}'", indent: indent+2)
	indent_puts("end", indent: indent+1)

	child_classes=[]
	props=[]

	json.each{|section, child|
		my_child_classes, my_props = iter(section, child, indent: indent+1)

		# todo: change to .merge.. needs some adjustmens, also e.g. for .inject({})
		child_classes += my_child_classes
		props += my_props
	}

	#STDERR.print [:my_props, props].inspect
	create_prop_methods(props, indent: indent)

	indent_puts "end # class #{section.camelcase}", indent: indent

	if class_type=='ArrayConfigClass'
		indent_puts("def #{section.camelcase(first_char: false).pluralize}", indent: indent)
		indent_puts("return @subclasses['#{section}']", indent: indent+1)
		indent_puts("end", indent: indent)

		str =<<eos
def #{section.gsub("-","_")}(*args, &block)
	array_class_setter(*args, klass: #{section.camelcase}, section: '#{section.to_s}', &block)
end
eos

		indent_puts(str, indent: indent)
	else # not class_type=='ArrayConfigClass'

		indent_puts "def #{section.gsub("-","_")}", indent: indent
		if indent==2 # skip adding a parent_instance for the first level ("Config")
			indent_puts "@subclasses['#{section}'] ||= #{section.camelcase}.new(parent_instance: nil, create_children: @create_children)", indent: indent+1
		else
			indent_puts "@subclasses['#{section}'] ||= #{section.camelcase}.new(parent_instance: self, create_children: @create_children)", indent: indent+1
		end
		indent_puts "end", indent: indent
	end
	
end

def create_prop_methods(props_array, indent:)
	props = props_array.inject({}){|h, v| h.merge!(v); h} # change from array to hash

	props.each{|k,v|
	if v.has_key?("regex")
		if v["regex"] == "^[^]'[]*$"
			v["regex"] = '^[^\]\'\[]*$'
		end
	end
	}

	indent_puts "@props=" + props.pretty_inspect, indent: indent+1

	props.keys.each{|prop|
		ruby_prop_name = prop.gsub("-","_").gsub(/^@/,"")

		indent_puts "# #{props[prop]["help-string"]}", indent: indent+1 if props[prop].has_key?("help-string")
		indent_puts "def #{ruby_prop_name}", indent: indent+1
		indent_puts "prop_get('#{prop}')", indent: indent+2
		indent_puts "end", indent: indent+1

		unless prop.include?("@")
			indent_puts "# #{props[prop]["help-string"]}", indent: indent+1 if props[prop].has_key?("help-string")
			indent_puts "def #{ruby_prop_name}=(val)", indent: indent+1
			indent_puts "prop_set('#{prop}', val)", indent: indent+2
			indent_puts "end", indent: indent+1
		end
	}
end



def iter_array(section, json, indent:)
	attr = json.delete('@attr')
	raise unless attr["node-type"]=='array' || attr["node-type"]=='union'

	# here we need to create the class for the array-class (e.g. "devices")
	indent_puts "class #{section.camelcase} < XML::ConfigClass", indent: indent

	indent_puts 'def has_multiple_values?', indent: indent+1
	indent_puts 'true', indent: indent+2
	indent_puts 'end', indent: indent+1

	indent_puts("def _section", indent: indent+1)
	indent_puts(":'#{section}'", indent: indent+2)
	indent_puts("end", indent: indent+1)

	child_classes=[]
	props=[]

	json.keys.each{|key| # key is something like "entry", which is a sequence
		#STDERR.puts(key)

		#indent_puts("class #{key.capitalize} < XML::Selector", indent: indent+2) # so we create a class for that...
		#selector = []

		my_child_classes, my_props = iter(key, json[key], indent: indent+1)

			child_classes += my_child_classes
			props += my_props

	}

	create_prop_methods(props, indent: indent)

	indent_puts "end # class #{section.camelcase}", indent: indent
	indent_puts "def #{section.gsub("-","_")}", indent: indent
	indent_puts "if @create_children", indent: indent+1
	indent_puts "@subclasses['#{section}'] ||= #{section.camelcase}.new(parent_instance: self, create_children: @create_children)", indent: indent+2
	indent_puts "else", indent: indent+1
	indent_puts "#{section.camelcase}.new(parent_instance: self)", indent: indent+2
	indent_puts "end", indent: indent+1
	indent_puts "end", indent: indent
end


File.open("../lib/interface/paloalto_config.rb","w"){|f|
	$f = f
	f.write("# generated: #{Time.now.to_s}\n")
	indent_puts(File.read("gen_config.template.rb"), indent: 0)

	iter_sequence('config', panorama_json['config'], indent: 2)
	indent_puts "end", indent: 1
	indent_puts "end", indent: 0
}


