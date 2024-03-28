# frozen_string_literal: true

require 'palo_alto'
load '/usr/share/panorama-api/new_op.rb'

a = { commit: { partial:
  { admin: ['admin'],
    'no-template': true,
    'no-template-stack': true,
    'no-log-collector': true,
    'no-log-collector-group': true,
    'no-wildfire-appliance': true,
    'no-wildfire-appliance-cluster': true,
    'device-and-network': 'excluded',
    'shared-object': 'excluded' } } }

b = { show: { devices: 'all' } }

c = { revert: { config: {
  partial: {
    admin: ['admin'],
    'no-template': true,
    'no-template-stack': true,
    'no-log-collector': true,
    'no-log-collector-group': true,
    'no-wildfire-appliance': true,
    'no-wildfire-appliance-cluster': true,
    'device-and-network': 'excluded',
    'shared-object': 'excluded'
  }
} } }

d = { commit: nil }

e = 'commit'

f = { revert: 'config' }

g = { show: 'templates' }

h = { show: 'devicegroups' }

j = { show: { jobs: { id: 12_431 } } }

k = { check: 'full-commit-required' }

l = { show: { config: { 'commit-scope': { partial: { admin: ['admin'] } } } } }

m = { show: { config: { 'commit-scope': { partial: { admin: %w[admin1 admin2] } } } } }

push_to_device = {	'commit-all': { 'shared-policy': { 'device-group': [{ name: 'TEST-DG' }] } } }

# validate:
p = {	'commit-all':
  {
    'shared-policy': {
      'device-group': [{ name: 'PLAYGROUND' }],
      'include-template': 'yes',
      'merge-with-candidate-cfg': 'yes',
      'force-template-values': 'no',
      'validate-only': 'yes'
    }
  } }

i = { show: { query: { result: { id: 10_438 } } } }

# hit counts:
device_group = 'PLAYGROUND'

hc1 = {
  show: {
    'rule-hit-count': {
      'device-group': [{
        name: device_group,
        'pre-rulebase': [{
          name: 'security',
          rules: ['all']
        }]
      }]
    }
  }
}

# hit count for one rule, with more details:
rule_name = 'Rule 27'
hc2 = {
  show: {
    'rule-hit-count': {
      'device-group': [{
        name: device_group,
        'pre-rulebase': [{
          name: 'security',
          rules: { 'rule-name': [{ name: rule_name }] }
        }]
      }]
    }
  }
}

client = PaloAlto::XML.new(host: 'panorama-test', username: 'admin', password: 'Admin123!', debug: %i[sent received])

[a, b, c, d, e, f, g, h, j, k, l, m, push_to_device, p, i, hc1, hc2].each do |cmd|
  puts client.op.to_xml(cmd)
  puts '---------------------------'
end
