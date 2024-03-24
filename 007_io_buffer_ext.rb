#!/usr/bin/env ruby

# frozen_string_literal: true

require "parallel"
require_relative "lib/io_buffer_hacks"

EOL = "\n".ord
SEMI = ";".ord

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

    value = buffer.get_string_until(offset, EOL)
    offset += value.bytesize

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
