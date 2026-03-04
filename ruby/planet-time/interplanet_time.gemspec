Gem::Specification.new do |s|
  s.name        = 'interplanet_time'
  s.version     = '0.1.0'
  s.summary     = 'Interplanetary time calculations — Ruby port of planet-time.js'
  s.description = 'Pure-Ruby library for planetary time, light-travel delay, and meeting windows across Earth and other solar system bodies.'
  s.authors     = ['InterPlanet']
  s.license     = 'MIT'
  s.files       = Dir['lib/**/*.rb']
  s.require_paths = ['lib']
  s.required_ruby_version = '>= 2.6'
end
