# frozen_string_literal: true

require 'palo_alto'

client = PaloAlto::XML.new(host: 'panorama-test', username: 'admin', password: 'Admin123!',
                           debug: %i[sent received statistics])
dg = 'PLAYGROUND'

# create a tag
tag_name = 'test'
new_tag = client.config.devices.entry(name: 'localhost.localdomain').device_group.entry(name: dg).tag.entry(name: tag_name).create!
new_tag.color = 'color23'
new_tag.set!

# get rules
# filtered rules:
# rules = client.config.devices.entry(name:'localhost.localdomain').device_group.entry(name: 'PLAYGROUND').pre_rulebase.security.rules
#                .entry{ (child(:source).child(:member).text == "Net_10.1.1.0-24").or(child(:destination).child(:member).text == 'Net_10.1.1.0-24') }
#                .get_all
#
# or:
#
# filter = (PaloAlto.child(:source).child(:member).text == "Net_10.1.1.0-24").or(PaloAlto.child(:destination).child(:member).text == 'Net_10.1.1.0-24')
# puts filter.to_xpath # prints generated Xpath filter
# => ./source/member/text()='Net_10.1.1.0-24'or./destination/member/text()='Net_10.1.1.0-24'
#
# rules = client.config.devices.entry(name:'localhost.localdomain').device_group.entry(name: 'PLAYGROUND').pre_rulebase.security.rules
#               .entry{filter}.get_all

# also more advanced filters are possible:
# filter = PaloAlto.not(PaloAlto.child(:'profile-setting').child(:group).child(:member) == 'IPS-Policy').and(
#   PaloAlto.parenthesis(
#     (PaloAlto.child(:tag).child(:member) == 'ips_enabled').or(
#       PaloAlto.child(:tag).child(:member) == 'ips_force_enabled'
#     )
#   )
# )
# puts filter.to_xpath
# => not(./profile-setting/group/member='IPS-Policy')and(./tag/member='ips_enabled'or./tag/member='ips_force_enabled')

rules = client.config.devices.entry(name: 'localhost.localdomain').device_group.entry(name: dg).pre_rulebase.security.rules.entry{}.get_all

rules.select! { |rule| rule.api_attributes['loc'] == dg } # filter rules inherited from upper device groups

pp rules
pp rules.length

rule = rules.first

pp rule.api_attributes # attributes like uuid and loc
pp rule.values # values as hash

rule.tag.member = [new_tag.name]
rule.group_tag = new_tag.name
rule.description += '....'
rule.edit!

# renaming rules
puts rule.to_xpath
rule.rename!('Test 1')
puts rule.to_xpath
puts rule.name

# Bulk changes on multiple rules:
rules = client.config.devices.entry(name: 'localhost.localdomain').device_group.entry(name: dg).pre_rulebase.security.rules.get

rules.entries.each do |name, rule|
  next unless rule.values.dig('profile-setting', 'group', 'member') == ['Internal-detect']
 
  rule.profile_setting.group.member = ['Internal']
  # to remove profile-setting: rule.delete_child('profile-setting')
end
puts "Pushing all rules to #{rules.to_xpath}"
rules.edit!

# create a new template
new_template = client.config.devices.entry(name: 'localhost.localdomain').template.entry(name: 'testtemplate').create!
new_template.set!

exit 0
