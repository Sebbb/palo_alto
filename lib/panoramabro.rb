# frozen_string_literal: true

require_relative './panoramabro/version'

# connection to panorama API
require_relative './interface/paloalto'

# core extensions
require_relative './panoramabro/core_extensions/ipaddr'
IPAddr.include CoreExtensions::IPAddr

# helper stuff
require_relative './panoramabro/helper/dynamic_instance_methods'

# internal helper modules
require_relative './panoramabro/api/helper/general'
require_relative './panoramabro/api/helper/where_used'
require_relative './panoramabro/api/helper/hit_count'
require_relative './panoramabro/api/helper/replace'
require_relative './panoramabro/api/helper/recursive_cleanup'

# panorama api client
require_relative './panoramabro/connection'

# internal classes
require_relative './panoramabro/api/base'
require_relative './panoramabro/api/collection'
require_relative './panoramabro/api/address_collection'
require_relative './panoramabro/api/service_collection'
require_relative './panoramabro/api/device_group'
require_relative './panoramabro/api/address_group'
require_relative './panoramabro/api/rule_base'
require_relative './panoramabro/api/service'
require_relative './panoramabro/api/service_group'

require_relative './panoramabro/api/rule/base'
require_relative './panoramabro/api/rule/nat'
require_relative './panoramabro/api/rule/security'

require_relative './panoramabro/api/ip_object/base'
require_relative './panoramabro/api/ip_object/ip_netmask'
require_relative './panoramabro/api/ip_object/ip_range'
require_relative './panoramabro/api/ip_object/fqdn'
require_relative './panoramabro/api/ip_object/any_object'

# the actual API for the outside
require_relative './panoramabro/device_group'
require_relative './panoramabro/address_group'
require_relative './panoramabro/ip_object'
require_relative './panoramabro/rule_base'
require_relative './panoramabro/rule'
require_relative './panoramabro/security_rule'
require_relative './panoramabro/nat_rule'
require_relative './panoramabro/service'
require_relative './panoramabro/service_group'
require_relative './panoramabro/search'

# Filter classes
require_relative './panoramabro/filter'
require_relative './panoramabro/filter/ip_object_filter'
require_relative './panoramabro/filter/address_group_filter'
require_relative './panoramabro/filter/rulebase_filter'

module Panoramabro; end
