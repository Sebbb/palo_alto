# frozen_string_literal: true

require 'json'
require 'pp'
panorama_json = JSON.parse(File.read('schema/panorama.json'))

$debug = false

class String
  alias _inspect inspect
  def inspect
    return _inspect if match(/[\t\n]/)

    "'#{gsub("'", "\\\\'")}'"
  end

  def camelcase(first_char: true)
    match(/\A[a-zA-Z0-9_-]*\z/) or raise 'invalid character'
    str = dup
    str[0] = 'K'.dup if str == 'class'
    str[0] = str[0].upcase if first_char
    str.gsub(/-(.)/) { |_e| Regexp.last_match(1).upcase }
  end

  def pluralize
    str = "#{self}s"
    str.gsub(/ys$/, 'ies').gsub(/ss$/, 'ses')
  end
end

def indent_puts(str, indent:)
  str.split("\n").each do |line|
    if $debug
      $f.puts(('  ' * indent + line).rstrip)
    else
      line = line&.split(' # ', 2).first unless line&.include?('rubocop:') || line&.include?("'")
      $f.puts(line.strip) if line && line&.strip != ''
    end
  end
end

def iter(child_key, child, indent:)
  raise 'iter: wrong class' unless child.is_a?(Hash)

  child_classes = []

  props = [] # name, validator
  child_attr = child['@attr']

  return if child_attr['prune-on']&.include?('non-fips-mode') || child_attr['prune-on']&.include?('non-cc-only-mode')

  case child_attr['node-type']
  when 'sequence'
    iter_sequence(child_key, child, indent: indent)
    child_classes << child_key

  when 'array'
    child_key = child_key.split('_').first
    iter_array(child_key, child, indent: indent)
    child_classes << child_key
    # pp child_key

  when 'element'
    # STDERR.puts "------------element------------"
    # STDERR.puts [:child_key, child_key].inspect
    # STDERR.puts child.inspect
    # STDERR.puts child_attr.inspect
    props << { child_key => child_attr }
  when 'union'
    # pp child_attr

    child_key = child_key.split('_').first
    iter_array(child_key, child, indent: indent)
    child_classes << child_key

    # props << {child_key => child_attr} # TODO: we may need to store this information as well
    # pp props
  when 'attr-req'
    props << { child_key => child_attr }
  when 'choice'
    # STDERR.puts "-------"
    # STDERR.puts child_key
    # STDERR.puts child_attr
    # STDERR.puts child

    child.delete('@attr')
    child.each_key do |k|
      # STDERR.puts [:k, k, child[k]].inspect
      my_child_classes, my_props = iter(k, child[k], indent: indent)
      props += my_props
      # STDERR.puts my_child_classes.inspect # TODO: I may need to do something with these as well!
      # pp k
      child_classes << k
      # props << {k => child[k]}
    end
  else
    pp json
    raise "unknown node-type: #{child_attr['node-type']}"
  end
  # pp props
  # pp child_classes

  [child_classes, props]
end

def puts_section(section, indent)
  indent_puts('def _section', indent: indent + 1)
  section_str = if section.include?('-')
                  ":'#{section}'"
                else
                  ":#{section}"
                end
  indent_puts(section_str, indent: indent + 2)
  indent_puts('end', indent: indent + 1)
end

def iter_sequence(section, json, indent:)
  if section.include?('__')
    section = section.split('__').first
  end
  attr = json.delete('@attr')
  raise unless attr['node-type'] == 'sequence'

  class_type = json.keys.any? { |k| k.start_with?('@') } ? 'ArrayConfigClass' : 'ConfigClass'

  indent_puts "class #{section.camelcase} < " + class_type, indent: indent

  indent_puts 'def has_multiple_values?; false; end', indent: indent + 1

  puts_section(section, indent)

  child_classes = []
  props = []

  json.each do |section, child|
    my_child_classes, my_props = iter(section, child, indent: indent + 1)

    next unless my_child_classes

    # TODO: change to .merge.. needs some adjustmens, also e.g. for .inject({})
    child_classes += my_child_classes
    props += my_props
  end

  # STDERR.print [:my_props, props].inspect
  create_prop_methods(props, indent: indent)

  indent_puts "end # class #{section.camelcase}", indent: indent

  if class_type == 'ArrayConfigClass'
    str = <<~EOS
      def selector_subclasses
        ['#{section}']
      end
      def #{section.camelcase(first_char: false).pluralize}
        return @subclasses['#{section}']
      end
      def #{section.gsub('-', '_')}(*args, &block)
        array_class_setter(*args, klass: #{section.camelcase}, section: '#{section}', &block)
      end
    EOS

    indent_puts(str, indent: indent)
  else # not class_type=='ArrayConfigClass'

    indent_puts "def #{section.gsub('-', '_')}", indent: indent
    if indent == 2 # skip adding a parent_instance for the first level ("Config")
      indent_puts "@subclasses['#{section}'] ||= #{section.camelcase}.new(parent_instance: nil, client: self, create_children: @create_children)",
                  indent: indent + 1
    else
      indent_puts "@subclasses['#{section}'] ||= #{section.camelcase}.new(parent_instance: self, client: @client, create_children: @create_children)",
                  indent: indent + 1
    end
    indent_puts 'end', indent: indent
  end
end

def create_prop_methods(props_array, indent:)
  props = props_array.each_with_object({}) { |v, h| h.merge!(v); } # change from array to hash

  props.each do |_k, v|
    next unless v.key?('regex')
    next if v['prune-on']&.include?('non-fips-mode') || v['prune-on']&.include?('non-cc-only-mode')

    v['regex'] = '^[^\]\'\[]*$' if v['regex'] == "^[^]'[]*$"
  end

  props.transform_keys! do |key|
    key.split('__').first
  end

  props.map { |_k, v| v.delete('memberof'); v.delete('autocomplete'); v.delete('loose-membership') }
  indent_puts "@props = #{props.inspect}", indent: indent + 1

  props.each_key do |prop|
    ruby_prop_name = prop.gsub('-', '_').gsub(/^@/, '')

    indent_puts "# #{props[prop]['help-string']}", indent: indent + 1 if props[prop].key?('help-string')
    indent_puts "def #{ruby_prop_name}", indent: indent + 1
    indent_puts "prop_get('#{prop}')", indent: indent + 2
    indent_puts 'end', indent: indent + 1

    next if prop.include?('@')

    indent_puts "# #{props[prop]['help-string']}", indent: indent + 1 if props[prop].key?('help-string')
    indent_puts "def #{ruby_prop_name}=(val)", indent: indent + 1
    indent_puts "prop_set('#{prop}', val)", indent: indent + 2
    indent_puts 'end', indent: indent + 1
  end
end

def iter_array(section, json, indent:)
  attr = json.delete('@attr')
  raise unless attr['node-type'] == 'array' || attr['node-type'] == 'union'

  # here we need to create the class for the array-class (e.g. "devices")
  indent_puts "class #{section.camelcase} < XML::ConfigClass", indent: indent

  indent_puts 'def has_multiple_values?; true; end', indent: indent + 1

  puts_section(section, indent + 1)

  child_classes = []
  props = []

  json.each_key do |key| # key is something like "entry", which is a sequence
    # STDERR.puts(key)

    # indent_puts("class #{key.capitalize} < XML::Selector", indent: indent+2) # so we create a class for that...
    # selector = []

    my_child_classes, my_props = iter(key, json[key], indent: indent + 1)

    child_classes += my_child_classes
    props += my_props
  end

  create_prop_methods(props, indent: indent)

  indent_puts "end # class #{section.camelcase}", indent: indent

  indent_puts "def #{section.gsub('-', '_')}", indent: indent
  indent_puts "maybe_register_subclass('#{section}', #{section.camelcase}.new(parent_instance: self, client: @client, create_children: @create_children))", indent: indent + 1
  indent_puts 'end', indent: indent
end

File.open("#{__dir__}/../lib/palo_alto/config.rb", 'w') do |f|
  $f = f
  f.write("# frozen_string_literal: true\n# generated: #{Time.now}\n")
  indent_puts(File.read('gen_config.template.rb'), indent: 0)

  iter_sequence('config', panorama_json['config'], indent: 2)
  indent_puts 'end', indent: 1
  indent_puts 'end', indent: 0
end
