require 'palo_alto'

xml = PaloAlto::XML.new(host: "panorama-test", port: "443", username: "admin", password: "Admin123!", debug: [:statistics, :warnings, :_sent, :_received])

query = "( full-path contains '/config/devices/entry[@name=\\'localhost.localdomain\\']/device-group/entry[@name=\\'gr\\']/address/entry[@name=\\'Blah_19\\']' )"
l=xml.log(query: query, log_type: 'config', nlogs: 50, show_detail: true, days: nil)

pp l.count
x = l.first
pp x


#################



ritm = 'RITM1234567'

def quote_string(v)
  "'" + v.to_s.gsub(/'/, "\\\\'") + "'"
end

query = "( ( cmd eq edit ) or ( cmd eq audit-commit ) ) and ( comment contains #{quote_string(ritm)} )"

l=xml.log(query: query, log_type: 'config', nlogs: 50, show_detail: true, days: nil)

pp l.count
