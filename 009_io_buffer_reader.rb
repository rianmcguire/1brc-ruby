#!/usr/bin/env ruby

# frozen_string_literal: true

require "parallel"
require_relative "lib/io_buffer_reader"

EOL = "\n".ord
SEMI = ";".ord

# New in Ruby 3.3.0 - we can enable YJIT without command-line options
RubyVM::YJIT.enable

Agg = Struct.new(:name, :min, :max, :sum, :count) do
  def initialize(name)
    super(name, 9999, -9999, 0, 0)
  end

  def add(value)
    self.min = value if value < min
    self.max = value if value > max
    self.sum += value
    self.count += 1
  end

  def merge(other)
    self.min = other.min if other.min < min
    self.max = other.max if other.max > max
    self.sum += other.sum
    self.count += other.count
  end

  def to_s
    # Convert integer values back to floats for output
    min = self.min / 10.0
    sum = self.sum / 10.0
    max = self.max / 10.0

    # chop! trailing ";" from name for output
    "#{name.chop!}=#{min}/#{(sum / count).round(1)}/#{max}"
  end
end

def process_chunk(buffer, offset, limit)
  stations = Hash.new { |h, k| h[k] = Agg.new(k) }

  reader = IO::Buffer::Reader.new(buffer, offset)
  if offset > 0
    # Discard the first line, as it might be incomplete
    reader.string_until(EOL)
  end

  loop do
    name = reader.string_until(SEMI)
    value = reader.parse_decimal_to_i

    stations[name].add(value)

    break if reader.offset >= limit
  end

  stations.values
end

buffer = IO::Buffer.map(File.open(ARGV[0]), nil, 0, IO::Buffer::READONLY)
size = buffer.size
chunk_size = 16 * 1024 * 1024
chunk_ranges = (0...size).step(chunk_size).chain([size]).each_cons(2)

# Merge each chunk of work into the final result as it finishes
merged = Hash.new { |h, k| h[k] = Agg.new(k) }
finish = ->(_, _, aggs) do
  aggs.each do |agg|
    merged[agg.name].merge(agg)
  end
end

buffer.locked do
  Parallel.each(chunk_ranges, finish:) { |offset, limit| process_chunk(buffer, offset, limit) }
end

puts "{#{merged.keys.sort.map { |name| merged[name] }.join(", ")}}"
