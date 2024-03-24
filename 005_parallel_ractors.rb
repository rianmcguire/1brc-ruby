#!/usr/bin/env -S ASDF_RUBY_VERSION=3.2.3 ruby --yjit

# ^ Running in Ruby 3.2.3, as there's a huge Ractor performance regression in 3.3.0:
# https://bugs.ruby-lang.org/issues/20112

# frozen_string_literal: true

require "etc"

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

Ractor.make_shareable(ARGV)

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
      pos += line.bytesize

      i = line.index(";")
      # Slice needs a length, but we want to take everything until the end of the line.
      # Rather than calculating it, the rules say the value will never be longer than "-99.9",
      # so we can allow for 5 characters + "\n".
      value = line.slice!(i + 1, 6)
      # After the `slice!`, line is now the name with a trailing ";"
      stations[line].add(value.to_f)

      break if pos >= limit
    end
  end

  stations.values
end

# Merge each chunk of work into the final result as it finishes
aggregator = Ractor.new do
  merged = Hash.new { |h, k| h[k] = Agg.new(k) }

  loop do
    aggs = Ractor.receive
    aggs.each do |agg|
      merged[agg.name].merge(agg)
    end
  end

  puts "{#{merged.keys.sort.map { |name| merged[name] }.join(", ")}}"
end

workers = Etc.nprocessors.times.map do
  Ractor.new(Ractor.current, aggregator) do |source, aggregator|
    loop do
      offset, limit = source.take
      result = process_chunk(offset, limit)
      aggregator.send(result)
    end
  end
end

size = File.size(ARGV[0])
chunk_size = 16 * 1024 * 1024
chunk_ranges = (0...size).step(chunk_size).chain([size]).each_cons(2)

chunk_ranges.each do |arg|
  Ractor.yield arg
end
# Close our port, so the workers exit when they finish their current chunk
Ractor.current.close_outgoing

# Wait for all workers to finish
until workers.empty?
  ractor, _ = Ractor.select(*workers)
  workers.delete(ractor)
end

# Tell the aggregator to finish up and print
aggregator.close_incoming
aggregator.take
