require 'palo_alto'

xml = PaloAlto::XML.new(host: "panorama-test", port: "443", username: "admin", password: "Admin123!", debug: [:sent, :received, :statistics])

