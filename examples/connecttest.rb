require 'palo_alto'

client = PaloAlto::XML.new(host: "panorama-test", username: "admin", password: "Admin123!", debug: [:sent, :received, :statistics])

