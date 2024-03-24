#!/usr/bin/env ruby

# frozen_string_literal: true

require "parallel"

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

def process_chunk(offset, limit)
  stations = Hash.new { |h, k| h[k] = Agg.new(k) }

  File.open(ARGV[0], "rb") do |f|
    f.seek(offset)
    # Keep track of the current position as a Ruby variable, so we don't have to call IO#pos.
    pos = offset

    if pos > 0
      # Discard the first line, as it might be incomplete
      pos += f.readline("\n").bytesize
    end

    f.each_line do |line|
      # line = "Vancouver;13.5\n"
      pos += line.bytesize

      i = line.index(";")
      # i = 9

      # Slice needs a length, but we want to take everything until the end of the line.
      # Rather than calculating it, the rules say the value will never be longer than "-99.9",
      # so we can allow for 5 characters + "\n".
      value = line.slice!(i + 1, 6)
      # value = "13.5\n"
      # line = "Vancouver;"

      stations[line].add(value.to_f)

      break if pos >= limit
    end
  end

  # Return the Aggs for this chunk back to the main process
  stations.values
end

size = File.size(ARGV[0])
chunk_size = 16 * 1024 * 1024
# Create chunk-sized ranges of [offset, limit] up to the file size
# eg. [[0, 16], [16, 32], [32, 64], [64, 66]]
chunk_ranges = (0...size).step(chunk_size).chain([size]).each_cons(2)

# Merge each chunk of work into the final result as it finishes
merged = Hash.new { |h, k| h[k] = Agg.new(k) }
finish = ->(_, _, aggs) do
  aggs.each do |agg|
    merged[agg.name].merge(agg)
  end
end

Parallel.each(chunk_ranges, finish:) { |offset, limit| process_chunk(offset, limit) }

puts "{#{merged.keys.sort.map { |name| merged[name] }.join(", ")}}"
