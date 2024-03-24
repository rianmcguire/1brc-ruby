#!/usr/bin/env ruby

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
    "#{name}=#{min}/#{(sum / count).round(1)}/#{max}"
  end
end

stations = Hash.new { |h, k| h[k] = Agg.new(k) }

File.open(ARGV[0], "rb") do |f|
  f.each_line do |line|
    name, value = line.split(";")
    stations[name].add(value.to_f)
  end
end

puts "{#{stations.keys.sort.map { |name| stations[name] }.join(", ")}}"
