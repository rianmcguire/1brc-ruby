#!/usr/bin/env ruby

# frozen_string_literal: true

require "parallel"
require_relative "lib/io_buffer_hacks"

EOL = "\n".ord # 10
SEMI = ";".ord # 59
MINUS = "-".ord
POINT = ".".ord
ZERO = "0".ord

# New in Ruby 3.3.0 - we can enable YJIT without command-line options
RubyVM::YJIT.enable

Agg = Struct.new(:name, :min, :max, :sum, :count) do
  def initialize(name)
    super(name, 999, -999, 0, 0)
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
    
    "#{name}=#{min}/#{(sum / count).round(1)}/#{max}"
  end
end

def process_chunk(string, offset, limit)
  stations = Hash.new { |h, k| h[k] = Agg.new(k) }

  if offset > 0
    # Discard the first line, as it might be incomplete
    # Search for offset of "\n"
    # Similar to: offset += f.readline("\n").bytesize
    while string.getbyte(offset) != EOL
      offset += 1
    end
    offset += 1
  end

  while offset < limit
    # Search for offset of ";"
    # Similar to: offset = line.index(";")
    name_start = offset
    while string.getbyte(offset) != SEMI
      offset += 1
    end
    # Create String for name
    # get_string(start_offset, length)
    # Similar to: name = line[name_start..offset]
    name = string.byteslice(name_start, offset - name_start)
    offset += 1

    # Assumes numbers have a single decimal digit, and results in an integer value in tenths of a degree.
    neg = false
    value = 0
    if string.getbyte(offset) == MINUS
      neg = true
      offset += 1
    end
    while (b = string.getbyte(offset)) != EOL
      if b != POINT
        value *= 10
        value += b - ZERO
      end
      offset += 1
    end
    value *= -1 if neg
    offset += 1

    s = stations[name]
    s.min = value if value < s.min
    s.max = value if value > s.max
    s.sum += value
    s.count += 1
  end

  stations.values
end

buffer = IO::Buffer.map(File.open(ARGV[0]), nil, 0, IO::Buffer::READONLY)
size = buffer.size
# TODO: why does performance get worse when we make this bigger?
chunk_size = 2 * 1024 * 1024
chunk_ranges = (0...size).step(chunk_size).chain([size]).each_cons(2)
string = buffer.get_string_unsafe

# Warm up YJIT
process_chunk(string, 0, 1024 * 1024)

# Merge each chunk of work into the final result as it finishes
merged = Hash.new { |h, k| h[k] = Agg.new(k) }
finish = ->(_, _, aggs) do
  aggs.each do |agg|
    merged[agg.name].merge(agg)
  end
end

Parallel.each(chunk_ranges, finish:) { |offset, limit| process_chunk(string, offset, limit) }

puts "{#{merged.keys.sort.map { |name| merged[name] }.join(", ")}}"
