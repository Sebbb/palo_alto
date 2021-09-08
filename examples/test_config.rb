require 'palo_alto'
require "byebug"

xml = PaloAlto::XML.new(host: "panorama-test", port: "443", username: "admin", password: "Admin123!", debug: [:sent, :received, :statistics])

#rules=xml.config.devices.entry(name:'localhost.localdomain').device_group.entry(name: 'PLAYGROUND').pre_rulebase.security.rules.entry{(child(:source).child(:member).text=="VPN_Net_10.1.1.0-24").or(child(:destination).child(:member).text == 'VPN_Net_10.1.1.0-24')}.get_all

rules=xml.config.devices.entry(name:'localhost.localdomain').device_group.entry(name: 'PLAYGROUND').pre_rulebase.security.rules.entry{}.get_all

pp rules
pp rules.length




tag_name='vpn:test'

tag = xml.config.devices.entry(name:'localhost.localdomain').device_group.entry(name: dg).tag.entry(name:tag_name).create!
tag.color = "color23"
tag.push!



dg='PLAYGROUND'
rules=xml.config.devices.entry(name:'localhost.localdomain').device_group.entry(name: dg).pre_rulebase.security.rules.entry{}.get_all
rules.reject!{|rule| rule.api_attributes['loc'] != dg}

pp rules.first.api_attributes # attributes like uuid and loc
pp rules.first.values()

r = rules.first
r.tag.member = [tag.name]
r.group_tag = tag.name
r.description += "...."
r.push!

puts r.to_xpath
r.rename!("Test 1")
puts r.to_xpath
pp r.name

exit 0

# create a new template with persisted subclasses
new_template = xml.config.devices.entry(name:'localhost.localdomain').template.entry(name: 'testtemplate').create!
new_template.push!




