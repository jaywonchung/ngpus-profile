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
def plot_hrange(event, begin, end, ax=None, label=''):
    w = [abs(e-b) for b, e in zip(begin, end)]
    if ax is None:
        _, ax = plt.subplots()
    ax.barh(event, width=w, left=begin, height=0.5, label=label)
    return ax


# %%
ax = plot_hrange(df.Worker, df.StartTime, df.EndTime)
ax.set_xlabel('Time')
ax.set_ylabel('Worker')


# %%
def extract_job_logs(path):
    path = Path(path)
    data = []
    reg = re.compile(r'\[(?P<Timestamp>[^\]]+)\] \[.+\] (?P<Event>Starting|Finish) .+\((?P<Iter>\d+), (?P<Unknown>\d+), (?P<JobId>\d+)\) at .+$')
    for log in path.glob('multiworker-output-*.log'):
        node = log.stem.split('-')[2]
        with log.open() as f:
            for line in f:
                m = reg.match(line)
                if not m:
                    continue
                d = {
                    'Node': int(node),
                }
                d.update(m.groupdict())
                data.append(d)
    df = pd.DataFrame(data)
    df['Timestamp'] = pd.to_datetime(df.Timestamp)
    for col in ['Iter', 'Unknown', 'JobId']:
        df[col] = pd.to_numeric(df[col])
    return df


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

total = pd.DataFrame()
for node in range(1, 6):
    df = pd.read_csv(f'log/2019-09-30T10:04:29/node{node}.csv', sep='\t',
                     names=['Iter', 'Unknown', 'JobId', 'StartTime', 'EndTime'])
    df['Node'] = node
    total = total.append(df)

#%%

total['StartTime'] = pd.to_datetime(total.StartTime)
total['EndTime'] = pd.to_datetime(total.EndTime)
fig, ax = plt.subplots(figsize=(12, 12))
for it in range(9):
    df = total[total.Iter == it]
    df = df.reset_index(drop=True)
    ax = plot_hrange(df.Node, df.StartTime, df.EndTime, ax=ax, label=str(it))
ax.legend()

#%%
total = pd.DataFrame()
for node in range(1, 5):
    df = pd.read_csv(f'log/2019-09-30T10:04:29/hyper{node}.csv', sep='\t',
                     names=['StartTime', 'EndTime', 'Node'])
    total = total.append(df)
total = total.reset_index(drop=True)
total['Node'] = pd.to_numeric(total.Node)
total['StartTime'] = pd.to_datetime(total.StartTime)
total['EndTime'] = pd.to_datetime(total.EndTime)


#%%

fig, ax = plt.subplots(figsize=(12, 12))
ax = plot_hrange(total.Node, total.StartTime, total.EndTime, ax=ax)
ax.legend()

#%%
