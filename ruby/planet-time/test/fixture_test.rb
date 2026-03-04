# frozen_string_literal: true

# fixture_test.rb — Cross-language fixture validation for the Ruby gem.
#
# Reads interplanet-github/c/fixtures/reference.json and validates
# get_planet_time() and light_travel_seconds() against reference values.
#
# Usage:
#   ruby -Ilib test/fixture_test.rb [path/to/reference.json]
#
# If the fixture file is not found, exits 0 with SKIP message.

require 'json'
require 'interplanet_time'

fixture_path = ARGV[0] || File.expand_path('../../c/fixtures/reference.json', __dir__)

unless File.exist?(fixture_path)
  puts "SKIP: fixture file not found at #{fixture_path}"
  puts '0 passed  0 failed  (fixtures skipped)'
  exit 0
end

data    = JSON.parse(File.read(fixture_path))
entries = data['entries']

passed  = 0
failed  = 0
count   = 0

def check(name, cond)
  if cond
    $passed_ref[0] += 1
  else
    $passed_ref[1] += 1
    puts "FAIL: #{name}"
  end
end

$passed_ref = [0, 0]

entries.each do |entry|
  utc_ms  = entry['utc_ms'].to_i
  planet  = entry['planet']
  exp_hr  = entry['hour'].to_i
  exp_min = entry['minute'].to_i
  lt_ref  = entry['light_travel_s']&.to_f

  begin
    pt  = InterplanetTime.get_planet_time(planet, utc_ms)
    tag = "#{planet}@#{utc_ms}"

    if pt.hour == exp_hr
      $passed_ref[0] += 1
    else
      $passed_ref[1] += 1
      puts "FAIL: #{tag} hour=#{exp_hr} (got #{pt.hour})"
    end

    if pt.minute == exp_min
      $passed_ref[0] += 1
    else
      $passed_ref[1] += 1
      puts "FAIL: #{tag} minute=#{exp_min} (got #{pt.minute})"
    end

    if lt_ref && planet != 'earth' && planet != 'moon'
      act_lt = InterplanetTime.light_travel_seconds('earth', planet, utc_ms)
      if (act_lt - lt_ref).abs <= 2.0
        $passed_ref[0] += 1
      else
        $passed_ref[1] += 1
        puts "FAIL: #{tag} lightTravel — expected #{lt_ref.round(3)}, got #{act_lt.round(3)}"
      end
    end

    count += 1
  rescue => e
    $passed_ref[1] += 1
    puts "FAIL: #{planet}@#{utc_ms} — #{e.message}"
  end
end

puts "Fixture entries checked: #{count}"
puts "#{$passed_ref[0]} passed  #{$passed_ref[1]} failed"

exit($passed_ref[1] > 0 ? 1 : 0)
