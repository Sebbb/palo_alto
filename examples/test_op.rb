require 'palo_alto'

a= {commit: { partial:[
  {'admin': ['admin']},
   'no-template',
   'no-template-stack',
   'no-log-collector',
   'no-log-collector-group',
   'no-wildfire-appliance',
   'no-wildfire-appliance-cluster',
   {'device-and-network': 'excluded'},
   {'shared-object': 'excluded'}
 ]}}

b= { show: {devices: 'all' } }

c = {revert: { config: {
 partial:[
  {'admin': ['admin']},
   'no-template',
   'no-template-stack',
   'no-log-collector',
   'no-log-collector-group',
   'no-wildfire-appliance',
   'no-wildfire-appliance-cluster',
   {'device-and-network': 'excluded'},
   {'shared-object': 'excluded'}
 ]}}}

d = {commit: nil}

e = 'commit'

f = {revert: 'config'}

g= {show: 'templates'}

h= {show: 'devicegroups'}

j={show: {jobs: {id: 12431}}}

k={check: 'full-commit-required'}

push_to_device={	'commit-all': { 'shared-policy': { 'device-group': [{name:'TEST-DG'}]}}}

#validate:
p={	'commit-all': 
	{
		'shared-policy': [
			{'device-group': [{name:'PLAYGROUND'}]},
			{'include-template':'yes'},
			{'merge-with-candidate-cfg':'yes'},
			{'force-template-values':'no'},
			{'validate-only':'yes'}
		]
	}
}

i = {show: {query: {result: {id: 10438 }}}}


# hit counts:
device_group = 'PLAYGROUND'

l = {
  show: {
    'rule-hit-count': [{
      'device-group': [{
        entry: [{
          name: device_group
        }, {
          "pre-rulebase": [{
            entry: [{
              name: 'security'
            }, {
              'rules': 'all'
            }]
          }]
        }]
      }]
    }]
  }
}

# hit count for one rule, with more details:
rule_name = "Rule 27"
l = {
  show: {
    'rule-hit-count': [{
      'device-group': [{
        entry: [{
          name: device_group
        }, {
          "pre-rulebase": [{
            entry: [{
              name: 'security'
            }, {
              'rules': {
                "rule-name": [{
                  entry: [{
                    name: rule_name
                  }]
                }]
              }
            }]
          }]
        }]
      }]
    }]
  }
}


client = PaloAlto::XML.new(host: "panorama-test", port: "443", username: "admin", password: "Admin123!", debug: [:sent, :received])

#pp client.op.execute(a)
#pp client.op.execute(b)
#pp client.op.execute(c)
pp client.op.execute(d)
puts "---------------------------"
pp client.op.execute(e)
puts "---------------------------"

#pp client.op.execute(f)

pp client.op.execute(k)

