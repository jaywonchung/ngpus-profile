# %%
import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path
import re

# %%
df = pd.read_csv('log/2019-09-22T20:35:20.229484/jobs.csv')
df['StartTime'] = pd.to_datetime(df['Start Time'])
df['EndTime'] = pd.to_datetime(df['End Time'])
df['Duration'] = df.EndTime - df.StartTime


# %%
def plot_hrange(event, begin, end):
    w = [abs(e-b) for b, e in zip(begin, end)]
    fig, ax = plt.subplots()
    ax.barh(event, width=w, left=begin, height=0.5)
    return ax


# %%
ax = plot_hrange(df.Worker, df.StartTime, df.EndTime)
ax.set_xlabel('Time')
ax.set_ylabel('Worker')


# %%
def extract_job_logs(path):
    path = Path(path)
    for log in path.glob('multiworker-output-*.log'):
        node = log.stem.split('-')[2]
        with log.open() as f:
            reg = re.compile(r'(Start|Finished) train')
            for line in f:
                m = reg.match(line)
                if not m:
                    continue


# %%
df = pd.read_csv('log/2019-09-23T10:57:58.166815/jobs.csv', sep='\t')
df['StartTime'] = pd.to_datetime(df.StartTime)
df['EndTime'] = pd.to_datetime(df.EndTime)
df['Duration'] = df.EndTime - df.StartTime
df['Worker'] = pd.to_numeric(df.Worker)

ax = plot_hrange(df.Worker, df.StartTime, df.EndTime)
ax.set_xlabel('Time')
ax.set_ylabel('Worker')


#%%
