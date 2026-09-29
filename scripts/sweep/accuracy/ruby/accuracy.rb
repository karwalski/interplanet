# Accuracy harness for ruby/planet-time (see ../gen-cases-group2.js).
# Run from ruby/planet-time:
#   ruby -Ilib ../../scripts/sweep/accuracy/ruby/accuracy.rb ../../scripts/sweep/accuracy/instants-group2.txt
require 'interplanet_time'

BODIES = %w[mercury venus earth mars jupiter saturn uranus neptune moon].freeze

def b(v) = v ? 1 : 0

File.readlines(ARGV[0]).map(&:strip).reject(&:empty?).each do |line|
  ms = Integer(line)
  BODIES.each do |body|
    begin
      pt = InterplanetTime.get_planet_time(body, ms)
      lt = InterplanetTime.light_travel_seconds(body, 'earth', ms)
    rescue StandardError => e
      warn "#{ms} #{body}: #{e.message}"
      next
    end
    puts [ms, body, pt.hour, pt.minute, pt.second, pt.day_number, pt.day_in_year,
          pt.year_number, pt.period_in_week, b(pt.is_work_period), b(pt.is_work_hour),
          format('%.6f', lt)].join("\t")
  end
  m = InterplanetTime.get_mtc(ms)
  puts [ms, 'mtc', m.sol, m.hour, m.minute, m.second].join("\t")
end
