# frozen_string_literal: true

require_relative 'lib/palo_alto/version'

Gem::Specification.new do |spec|
  spec.name          = 'palo_alto'
  spec.version       = PaloAlto::VERSION
  spec.authors       = ['Sebastian Roesner']
  spec.email         = ['sroesner-paloalto@roesner-online.de']

  spec.summary       = 'Palo Alto API for Ruby'
  spec.homepage      = 'https://github.com/Sebbb/'
  spec.license       = 'artistic-2.0'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata["source_code_uri"]   = 'https://github.com/Sebbb/palo_alto/'
  spec.metadata["changelog_uri"]     = 'https://github.com/Sebbb/palo_alto/blob/main/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features|_generators|bin|pkg|.env)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'nokogiri', '~> 1.10'
end
