#!/usr/bin/env ruby
# frozen_string_literal: true

require "polars"

results = Polars.scan_csv(ARGV[0], sep: ";", has_header: false)
  .groupby("column_1")
  .agg([
    Polars.col("column_2").min.alias("min"),
    Polars.col("column_2").mean.alias("mean"),
    Polars.col("column_2").max.alias("max")
  ])
  .sort("column_1")
  .collect(allow_streaming: true)
  .iter_rows
  .map do |name, min, mean, max|
    "#{name}=#{min}/#{mean.round(1)}/#{max}"
  end

puts "{#{results.join(", ")}}"
