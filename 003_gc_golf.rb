#!/usr/bin/env ruby

# frozen_string_literal: true

# New in Ruby 3.3.0 - we can enable YJIT without command-line options
RubyVM::YJIT.enable

Agg = Struct.new(:name, :min, :max, :sum, :count) do
  def initialize(name)
    super(name, Float::INFINITY, -Float::INFINITY, 0, 0)
  end

  def add(value)
    self.min = value if value < min
    self.max = value if value > max
    self.sum += value
    self.count += 1
  end

  def to_s
    # chop! trailing ";" from name for output
    "#{name.chop!}=#{min}/#{(sum / count).round(1)}/#{max}"
  end
end

stations = Hash.new { |h, k| h[k] = Agg.new(k) }

def count_allocated
  before = GC.stat(:total_allocated_objects)
  begin
    yield
  ensure
    after = GC.stat(:total_allocated_objects)
    puts "allocated: #{after - before}"
  end
end

File.open(ARGV[0], "rb") do |f|
  f.each_line do |line|
    # line = "Vancouver;13.5\n"

    i = line.index(";")
    # i = 9

    # Slice needs a length, but we want to take everything until the end of the line.
    # Rather than calculating it, the rules say the value will never be longer than "-99.9",
    # so we can allow for 5 characters + "\n".
    value = line.slice!(i + 1, 6)
    # value = "13.5\n"
    # line = "Vancouver;"

    stations[line].add(value.to_f)
  end
end

puts "{#{stations.keys.sort.map { |name| stations[name] }.join(", ")}}"
