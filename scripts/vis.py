import numpy as np
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


def job_timeline(workers, begin, end, groupby=None, label=None,
                 ax=None,
                 marker_begin=None, marker_end=None,
                 markersize=None,
                 group_num=2, group_radius=.3):
    '''
        Args:
            workers: list
            begin: list
            end: list
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
        if not len(workers) == len(begin) == len(end) == len(groupby):
            raise ValueError('Length of workers, begin, end, groupby should be equal,'
                             f' but got ({len(workers)}, {len(begin)}, {len(end)}, {len(groupby)})')

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

    def draw_group(y, xmin, xmax, key=None):
        # cycle color
        c = next(ax._get_lines.prop_cycler)['color']
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
    else:
        for grp_key in np.unique(groupby):
            mask = groupby == grp_key
            y = y_pos[mask]
            xmin = begin[mask]
            xmax = end[mask]
            draw_group(y, xmin, xmax, key=grp_key)

    # fix yticks to categorical
    ax.yaxis.set_major_formatter(mticker.IndexFormatter(y_values))
    ax.yaxis.set_major_locator(mticker.MultipleLocator(1.0))

    # set a default title
    ax.set_ylabel('Worker')
    ax.set_xlabel('Time')

    return ax
