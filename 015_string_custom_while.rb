#!/usr/bin/env -S ruby --yjit-call-threshold=1

# frozen_string_literal: true

require "etc"
require "socket"
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
chunk_size = 16 * 1024 * 1024
chunk_ranges = (0...size).step(chunk_size).chain([size]).each_cons(2).to_a
string = buffer.get_string_unsafe

# Warm up YJIT
warmup = <<INPUT
Havana;23.6
Havana;23.6
Havana;23.6
Havana;-23.6
Havana;43.6
INPUT
process_chunk(warmup, 1, warmup.bytesize)

work_rd, work_wr = UNIXSocket.pair(:DGRAM)

# TODO: This shouldn't work?
result_rd, result_wr = UNIXSocket.pair

Process.warmup

Etc.nprocessors.times do
  Process.fork do
    while true
      offset, limit = Marshal.load(work_rd)
      break unless offset
      result = process_chunk(string, offset, limit)
      result_wr.send Marshal.dump(result), 0
    end
  end
end

sender = Thread.new do
  chunk_ranges.each do |range|
    work_wr.send Marshal.dump(range), 0
  end
  Etc.nprocessors.times do
    work_wr.send Marshal.dump(nil), 0
  end
end

# Merge each chunk of work into the final result as it finishes
merged = Hash.new { |h, k| h[k] = Agg.new(k) }
finished = 0
while true
  aggs = Marshal.load(result_rd)
  aggs.each do |agg|
    merged[agg.name].merge(agg)
  end
  finished += 1

  break if finished == chunk_ranges.length
end

puts "{#{merged.keys.sort.map { |name| merged[name] }.join(", ")}}"

Process.waitall
