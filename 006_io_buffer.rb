#!/usr/bin/env ruby

# frozen_string_literal: true

require "parallel"

EOL = "\n".ord # 10
SEMI = ";".ord # 59

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

  def merge(other)
    self.min = other.min if other.min < min
    self.max = other.max if other.max > max
    self.sum += other.sum
    self.count += other.count
  end

  def to_s
    # chop! trailing ";" from name for output
    "#{name}=#{min}/#{(sum / count).round(1)}/#{max}"
  end
end

def process_chunk(buffer, offset, limit)
  stations = Hash.new { |h, k| h[k] = Agg.new(k) }

  if offset > 0
    # Discard the first line, as it might be incomplete
    # Search for offset of "\n"
    while buffer.get_value(:U8, offset) != EOL
      offset += 1
    end
    offset += 1
  end

  loop do
    # Search for offset of ";"
    name_start = offset
    while buffer.get_value(:U8, offset) != SEMI
      offset += 1
    end
    # Create String for name
    # get_string(start_offset, length)
    name = buffer.get_string(name_start, offset - name_start)
    offset += 1

    # Search for offset of "\n"
    value_start = offset
    while buffer.get_value(:U8, offset) != EOL
      offset += 1
    end
    # Create String for value
    value = buffer.get_string(value_start, offset - value_start)
    offset += 1

    stations[name].add(value.to_f)

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
