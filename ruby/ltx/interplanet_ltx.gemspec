Gem::Specification.new do |s|
  s.name        = 'interplanet_ltx'
  s.version     = '1.0.0'
  s.summary     = 'LTX (Light-Time eXchange) protocol library — Ruby port of ltx-sdk.js'
  s.description = 'Pure-Ruby library for creating, encoding, and decoding LTX session plans for interplanetary real-time communication.'
  s.authors     = ['InterPlanet']
  s.license     = 'MIT'
  s.files       = Dir['lib/**/*.rb']
  s.require_paths = ['lib']
  s.required_ruby_version = '>= 2.6'
end
