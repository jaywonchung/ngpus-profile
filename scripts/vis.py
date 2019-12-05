import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from matplotlib.path import Path as mPath


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
    except:
        c = color
    c = colorsys.rgb_to_hls(*mc.to_rgb(c))
    return colorsys.hls_to_rgb(c[0], max(0, min(1, amount * c[1])), c[2])


# http://stackoverflow.com/q/3844931/
def check_equal(lst):
    '''
    Return True if all elements in the list are equal
    '''
    return not lst or [lst[0]]*len(lst) == lst


def gen_groupby(*args, groups):
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
    groups = pd.concat(groups, axis=1)
    keys = groups.drop_duplicates()
    
    for _, grp_key in keys.iterrows():
        mask = (groups == grp_key).all(axis=1)
        yield grp_key, [arg[mask] for arg in args]


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
        draw_group(y_pos, begin, end)
    if not isinstance(groupby, list):
        groupby = [groupby]
    
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
