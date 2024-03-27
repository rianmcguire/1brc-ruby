#!/usr/bin/env ruby

# frozen_string_literal: true

require "parallel"
require_relative "lib/io_buffer_hacks"

EOL = "\n".ord
SEMI = ";".ord
MINUS = "-".ord
POINT = ".".ord
ZERO = "0".ord

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

  if offset > 0
    # Discard the first line, as it might be incomplete
    offset += buffer.get_string_until(offset, EOL).bytesize
  end

  loop do
    name = buffer.get_string_until(offset, SEMI)
    offset += name.bytesize

    # Assumes numbers have a single decimal digit, and results in an integer value in tenths of a degree.
    # eg. "42.3\n" -> 423
    neg = false
    value = 0
    if buffer.get_value(:U8, offset) == MINUS
      neg = true
      offset += 1
    end
    while (b = buffer.get_value(:U8, offset)) != EOL
      if b != POINT
        value *= 10
        # ZERO = "0".ord == 48
        # "1".ord == 49
        # "2".ord == 50
        # "3".ord == 51
        # "4".ord == 52
        value += b - ZERO
      end
      offset += 1
    end
    value *= -1 if neg
    offset += 1

    stations[name].add(value)

    break if offset >= limit
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

Parallel.each(chunk_ranges, finish:) { |offset, limit| process_chunk(buffer, offset, limit) }

puts "{#{merged.keys.sort.map { |name| merged[name] }.join(", ")}}"
