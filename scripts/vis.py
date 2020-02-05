from __future__ import annotations

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from matplotlib.path import Path as mPath
from pathlib import Path
import re
import json
import copy


from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from typing import Sequence, List


def default_marker_begin():
    return mPath([
        (-0.5, 0.866),
        (0, 0),
        (0, 1.0),
        (0, -1.0),
        (0, 0),
        (-0.5, -0.866),
        (0, 0),
    ])


def default_marker_end():
    return mPath([
        (0.5, 0.866),
        (0, 0),
        (0, 1.0),
        (0, -1.0),
        (0, 0),
        (0.5, -0.866),
        (0, 0),
    ])


# a namespace variable
class NameSpace:
    pass


d = NameSpace()


def subplots(name, **kwargs):
    figsize = kwargs.pop('figsize', None)
    constrained_layout = kwargs.pop('constrained_layout', True)

    plt.close(name)
    fig = plt.figure(name,
                     # figsize doesn't work with jupyter-matplotlib yet,
                     # see https://github.com/matplotlib/jupyter-matplotlib/issues/117
                     # figsize=figsize,
                     constrained_layout=constrained_layout,
                     clear=True)
    if figsize:
        if hasattr(fig.canvas, 'layout'):
            w, h = figsize
            if w:
                fig.canvas.layout.width = str(w) + 'in'
            if h:
                fig.canvas.layout.height = str(h) + 'in'
        else:
            w, h = figsize
            dw, dh = plt.rcParams['figure.figsize']
            fig.set_size_inches(w or dw, h or dh)
    axes = fig.subplots(**kwargs)

    return fig, axes


def legend(ax, **kwargs):
    bbox_to_anchor = kwargs.pop('bbox_to_anchor', (0.5, 1))
    loc = kwargs.pop('loc', 'lower center')
    ax.legend(bbox_to_anchor=bbox_to_anchor, loc=loc, **kwargs)
    # fig.subplots_adjust(top=0.86)


def adjust_lightness(color, amount=0.5):
    '''
    the color gets brighter when amount > 1 and darker when amount < 1
    '''
    import matplotlib.colors as mc
    import colorsys
    try:
        c = mc.cnames[color]
    except KeyError:
        c = color
    c = colorsys.rgb_to_hls(*mc.to_rgb(c))
    return colorsys.hls_to_rgb(c[0], max(0, min(1, amount * c[1])), c[2])


# http://stackoverflow.com/q/3844931/
def check_equal(lst):
    '''
    Return True if all elements in the list are equal
    '''
    return not lst or [lst[0]]*len(lst) == lst


def gen_groupby(*args: pd.Series, groups: List[pd.Series]):
    '''
    group args by groups.
    Each args should be list-like, groups should be a list of list-like.
    Each of them should be of the same length
    '''
    if len(args) == 0 or len(groups) == 0:
        raise ValueError('args or groups must be non-empty')

    groups = tuple(groups)
    lens = [len(col) for col in args + groups]
    if not check_equal(lens):
        raise ValueError(f'args + groups of different length, got {lens}')

    # create a dataframe from group keys
    groups: pd.DataFrame = pd.concat(groups, axis=1)
    keys = groups.drop_duplicates()

    for _, grp_key in keys.iterrows():
        mask = (groups == grp_key).all(axis=1)
        yield grp_key, [arg[mask] for arg in args]


def fuzzy_slug(slug):
    '''Given a slug, find a log_dir'''
    base_dir = Path('log')
    log_dir = base_dir / slug
    if not log_dir.is_dir():
        # try substr match
        candidates = [p for p in base_dir.glob(f'*{slug}*') if p.is_dir()]
        if len(candidates) == 1:
            log_dir = candidates[0]
            print(f'Using existing log_dir: {log_dir.name}')
            return log_dir
        elif len(candidates) > 1:
            raise ValueError(f'Multiple matches, use more specific name: {candidates}')
    raise ValueError(f'Log dir {log_dir} does not exist')


def normalize_time(cols, ref=None):
    if not cols:
        return cols
    if ref is None:
        ref = cols[0].min()
    return [
        (col - ref).astype('timedelta64[s]')
        for col in cols
    ]

def job_timeline(workers, begin, end,
             groupby=None, label=None,
             ax=None,
             marker_begin=None, marker_end=None,
             markersize=None,
             group_num=2, group_radius=.3):
    '''
        Args:
            workers: list
            begin: list
            end: list
            inner_stage: list
            groupby: list
    '''
    if marker_begin is None:
        marker_begin = default_marker_begin()
    if marker_end is None:
        marker_end = default_marker_end()

    if int(group_num) <= 0:
        raise ValueError(f'group_num should be a positive integer, but got {group_num}')
    group_num = int(group_num)

    if groupby is None:
        if not len(workers) == len(begin) == len(end):
            raise ValueError('Length of workers, begin, end should be equal,'
                             f' but got ({len(workers)}, {len(begin)}, {len(end)})')
    else:
        if not isinstance(groupby, list):
            groupby = [groupby]

        lens = [len(col) for col in [workers, begin, end] + groupby]
        if not check_equal(lens):
            raise ValueError('Length of workers, begin, end, and col in groupby should be equal,'
                             f' but got {lens}')

    # create y_pos according to workers, so workers doesn't has to be numeric
    y_values, y_pos = np.unique(workers, return_inverse=True)
    y_pos = y_pos.astype(np.float64)

    # adjust y_pos according to a wave like shape around original y_pos,
    # the offset should be changing based on the index within a particular y_value
    offset_pattern = np.concatenate([
        np.arange(0, group_num),
        np.arange(group_num, -group_num, step=-1),
        np.arange(-group_num, 0)
    ])
    for worker in y_values:
        mask = workers == worker
        num = len(workers[mask])
        offset = np.tile(offset_pattern, (num + len(offset_pattern) - 1) // len(offset_pattern))[:num]
        y_pos[mask] += offset * group_radius / group_num

    if ax is None:
        _, ax = plt.subplots()

    def draw_group(y, xmin, xmax, c, key=None):
        # label
        if key is None:
            theLabel = label
        else:
            theLabel = (label or '{key}').format(key=key) if key is not None else label
        # draw lines
        ax.hlines(y, xmin, xmax, label=theLabel, color=c)
        # draw markers
        ax.plot(xmin, y, color=c,
                marker=marker_begin, markersize=markersize,
                linestyle='None', fillstyle='none')
        ax.plot(xmax, y, color=c,
                marker=marker_end, markersize=markersize,
                linestyle='None', fillstyle='none')

    if groupby is None:
        c = next(ax._get_lines.prop_cycler)['color']
        draw_group(y_pos, begin, end, c)
    else:
        if len(groupby) >= 1 and len(groupby) <= 2:
            # cycle color
            c = next(ax._get_lines.prop_cycler)['color']
            colors = {}
            for grp_key, (y, xmin, xmax) in gen_groupby(y_pos, begin, end, groups=groupby):
                if grp_key[0] not in colors:
                    colors[grp_key[0]] = next(ax._get_lines.prop_cycler)['color']
                c = colors[grp_key[0]]
                if len(grp_key) >= 2:
                    c = adjust_lightness(c, 1.5 - grp_key[1] * 0.3)
                draw_group(y, xmin, xmax, c, key=grp_key)
        else:
            raise ValueError('Unsupported groupby')

    # fix yticks to categorical
    ax.yaxis.set_major_formatter(mticker.IndexFormatter(y_values))
    ax.yaxis.set_major_locator(mticker.MultipleLocator(1.0))

    # set a default title
    ax.set_ylabel('Worker')
    ax.set_xlabel('Time')

    return ax


def idfy(name):
    '''Given a name, return a encoded str sutiable as ID'''
    name = name.replace('-', '_')
    if name[0].isdigit():
        name = '_' + name
    return name


def save_global(slug, name, df):
    slug = idfy(slug)
    name = idfy(name)
    try:
        ns = getattr(d, slug)
    except AttributeError:
        ns = NameSpace()
        setattr(d, slug, ns)
    setattr(ns, name, df)


def load_jobs(slug, tag=''):
    # find log dir
    log_dir = fuzzy_slug(slug)

    # find file
    if tag:
        tag = tag + '-'
    csv_file = log_dir / f'{tag}jobs.csv'
    if not csv_file.is_file():
        # try glob
        for csv_file in log_dir.glob(f'*{tag}jobs.csv'):
            if csv_file.is_file():
                break
            raise ValueError(f'CSV file {csv_file} does not exist')
        else:
            raise ValueError(f'CSV file {csv_file} does not exist')

    # load it
    assert csv_file.is_file()
    print(f'Loading {csv_file}')
    total = pd.read_csv(str(csv_file))
    for col in ['StartTime', 'EndTime']:
        total[col] = pd.to_datetime(total[col])
    for col in ['Budget', 'Iter', 'Rung', 'JobId', 'Epoches', 'Node']:
        total[col] = pd.to_numeric(total[col])
    total['Duration'] = (total.EndTime - total.StartTime).astype('timedelta64[s]')
    total = total.sort_values(by=['Iter', 'Rung', 'JobId'])

    # save it under a global name
    save_global(slug, csv_file.stem[csv_file.stem.find('name-') + 5:-5], total)
    return total


def load_jobs_v2(slug, tag):
    # find log dir
    log_dir = fuzzy_slug(slug)

    # find file
    jl_file = log_dir / f'{tag}.jsonl'
    if not jl_file.is_file():
        # try glob
        for jl_file in log_dir.glob(f'*{tag}*.jsonl'):
            if jl_file.is_file():
                break
            raise ValueError(f'JSONL file {jl_file} does not exist')

    # load it
    print(f'Loading {jl_file}')
    ptn_node = re.compile(r'node-(?P<node>\d+)')
    with jl_file.open() as f:
        data = []
        for line in f:
            job = json.loads(line)['job']
            j = {}
            j['Iter'], j['Rung'], j['JobId'] = job['id']
            j['SubmitTime'] = job['timestamps']['submitted']
            j['StartTime'] = job['timestamps']['started']
            j['EndTime'] = job['timestamps']['finished']
            j['Budget'] = job['kwargs']['budget']
            j['Epoches'] = job['result']['epoch']
            j['NumWorker'] = len(job['worker_name'])
            j['SkippedCount'] = job['skipped_count']
            j['OptNum'] = job['opt_num']
            j['Raw'] = job

            if 'estimator_info' in job:
                if 'est_run' in job['estimator_info']:
                    j['EstRun'] = job['estimator_info']['est_run']
                else:
                    j['EstRun'] = 0

            # compatibility with old plotting code
            for node in job['worker_name']:
                j = copy.deepcopy(j)
                j['Node'] = int(ptn_node.search(node).group('node'))
                data.append(j)

    total = pd.DataFrame(data)

    for col in ['StartTime', 'EndTime', 'SubmitTime']:
        total[col] = pd.to_datetime(total[col], unit='s')
    for col in ['Budget', 'Iter', 'Rung', 'JobId', 'Epoches', 'Node', 'NumWorker', 'SkippedCount', 'OptNum', 'EstRun']:
        if col in total:
            total[col] = pd.to_numeric(total[col])
    total['Duration'] = (total.EndTime - total.StartTime).astype('timedelta64[s]')
    total = total.sort_values(by=['Iter', 'Rung', 'JobId']).reset_index(drop=True)

    # save it under a global name
    save_global(slug, jl_file.stem[jl_file.stem.find('name-') + 5:], total)
    return total


def timelines(slug, names, title='', relative=False, **kwargs):
    fig, axs = subplots(f'Auto-PyTorch with {slug} {title}', squeeze=False, sharex=True, nrows=len(names), **kwargs)

    # get the full slug
    _, slug = fuzzy_slug(slug).name.split('-', 1)

    # get df
    dfs = [
        (name, getattr(getattr(d, idfy(slug)), idfy(name)))
        for name in names
    ]
    # find a ref point
    ref = min(df.StartTime.min() for _, df in dfs)

    for ax, (name, df) in zip(axs.flatten(), dfs):
        if relative:
            start, end = normalize_time([df.StartTime, df.EndTime])
        else:
            diff = df.StartTime.min() - ref
            start, end = df.StartTime - diff, df.EndTime - diff
        job_timeline(df.Node, start, end, groupby=[df.Iter, df.Rung],
                     label='Iter {key[0]} Rung {key[1]}', ax=ax)
        legend(ax, ncol=5, bbox_to_anchor=(0.5, 1.18))
        ax.set_title(name)

    return fig, axs


def loss_over_time(start, end, raw, **kwargs):
    _, time = normalize_time([start, end])
    
    loss = raw.apply(lambda obj: obj['result']['loss'])
    df = pd.DataFrame({'Time': time, 'Loss': loss}).sort_values('Time')
    df['MinLoss'] = df.Loss.cummin()
    
    kwargs['drawstyle'] = 'steps-pre'
    ax = df.plot(x='Time', y='MinLoss', **kwargs)
    ax.set_ylim([0, 1])
    ax.set_xlim([0, ax.get_xlim()[1]])
    return ax

def losses(slug, names, title='', **kwargs):
    fig, ax = subplots(f'Loss over time for {slug} {title}', **kwargs)
    
    _, slug = fuzzy_slug(slug).name.split('-', 1)
    
    dfs = [
        (name, getattr(getattr(d, idfy(slug)), idfy(name)))
        for name in names
    ]
    
    for name, df in dfs:
        loss_over_time(df.StartTime, df.EndTime, df.Raw, ax=ax, label=name)
    return fig, ax