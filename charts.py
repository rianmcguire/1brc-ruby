#!/usr/bin/env python

import plotly.express as px
import numpy as np
import pandas as pd

input_factor = {
    "measurements_1M.txt": 1000,
    "measurements_10M.txt": 100,
    "measurements_100M.txt": 10,
    "measurements_1B.txt": 1,
}

df = pd.read_csv('results.csv')
df['projected_mean'] = df.apply(lambda row: row['mean'] * input_factor[row['input']], axis=1)

for i in range(2, len(df) + 1):
    fig = px.bar(
        df.head(i),
        x='command',
        y='projected_mean',
        # log_y=True,
        labels={
            "projected_mean": "Time (s)",
        },
        text_auto=".4r",
    )
    fig.update_traces(textangle=0, cliponaxis=False, textposition="outside")
    fig.update_layout(yaxis_tickformat = ".1r", xaxis_title=None)

    fig.write_image(f"fig{i}.svg")

df = pd.read_csv('thermal.csv')
fig = px.line(
    df,
    y=['amd', 'm2'],
    title="010_polars.rb measurements_100M.txt",
    labels={
        "variable": "CPU",
        "index": "Consecutive runs",
        "value": "Time (s)"
    }
)
fig.update_layout(title_x=0.5, yaxis_range=[0, 2.3], xaxis_range=[0,100])
fig.write_image(f"thermal.svg")

df = pd.read_csv('proc.csv')
fig = px.line(
    df,
    x='threads',
    y='mean',
    title="005_parallel_processes.rb measurements_100M.txt",
    labels={
        "threads": "Number of threads",
        "mean": "Time (s)"
    }
)
fig.write_image(f"proc.svg")
