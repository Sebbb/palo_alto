require 'palo_alto'

client = PaloAlto::XML.new(host: "panorama-test", username: "admin", password: "Admin123!", debug: [:sent, :received, :statistics])
dg = 'PLAYGROUND'

# create a tag
tag_name = 'test'

new_tag = client.config.devices.entry(name: 'localhost.localdomain').device_group.entry(name: dg).tag.entry(name: tag_name).create!
new_tag.color = 'color23'
new_tag.push!

# filtered rules:
# rules = client.config.devices.entry(name:'localhost.localdomain').device_group.entry(name: 'PLAYGROUND').pre_rulebase.security.rules
#                .entry{ (child(:source).child(:member).text == "Net_10.1.1.0-24").or(child(:destination).child(:member).text == 'Net_10.1.1.0-24') }
#                .get_all
#
# or:
#
# filter = (PaloAlto.child(:source).child(:member).text == "Net_10.1.1.0-24").or(PaloAlto.child(:destination).child(:member).text == 'Net_10.1.1.0-24')
# puts filter.to_xpath
# => ./source/member/text()='Net_10.1.1.0-24'or./destination/member/text()='Net_10.1.1.0-24'
#
# rules = client.config.devices.entry(name:'localhost.localdomain').device_group.entry(name: 'PLAYGROUND').pre_rulebase.security.rules
#               .entry{filter}.get_all
#
# also more advanced filters are possible:
# PaloAlto.not(PaloAlto.child(:'profile-setting').child(:group).child(:member) == 'IPS-Policy').and(
#   PaloAlto.parenthesis(
#     (PaloAlto.child(:tag).child(:member) == 'ips_enabled').or(
#       PaloAlto.child(:tag).child(:member) == 'ips_force_enabled'
#     )
#   )
# ).to_xpath
#
# => not(./profile-setting/group/member='IPS-Policy')and(./tag/member='ips_enabled'or./tag/member='ips_force_enabled')

rules = client.config.devices.entry(name: 'localhost.localdomain').device_group.entry(name: dg).pre_rulebase.security.rules.entry{}.get_all

rules.reject! { |rule| rule.api_attributes['loc'] != dg } # remove rules inherited from upper device groups from array

pp rules
pp rules.length

pp rules.first.api_attributes # attributes like uuid and loc
pp rules.first.values() # values as hash

rule = rules.first
rule.tag.member = [new_tag.name]
rule.group_tag = new_tag.name
rule.description += '....'
rule.push!

puts rule.to_xpath
rule.rename!('Test 1')
puts rule.to_xpath
pp rule.name

exit 0

# create a new template
new_template = client.config.devices.entry(name:'localhost.localdomain').template.entry(name: 'testtemplate').create!
new_template.push!
