from datetime import datetime
from pathlib import Path
from collections import OrderedDict
import shutil

from invoke import task
from invoke.exceptions import Exit, UnexpectedExit, Failure
from fabric import Connection, ThreadingGroup as Group

from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from typing import Optional


CLUSTER = 'clemson'

# will be modified by host selector tasks
TARGETS = []

# Top level dir
TOP_LEVEL = Path(__file__).parent


def sizeof_fmt(num, suffix='B'):
    for unit in ['', 'Ki', 'Mi', 'Gi', 'Ti', 'Pi', 'Ei', 'Zi']:
        if abs(num) < 1024.0:
            return "%3.1f%s%s" % (num, unit, suffix)
        num /= 1024.0
    return "%.1f%s%s" % (num, 'Yi', suffix)


@task
def all(c):
    global TARGETS
    nodes = [1, 2, 3, 4, 5]
    print(f'Running on all nodes: {nodes}')
    TARGETS += [hostname(n) for n in nodes]


@task
def wk(c):
    global TARGETS
    nodes = [2, 3, 4, 5]
    print(f'Running on worker nodes: {nodes}')
    TARGETS += [hostname(n) for n in nodes]


@task
def ms(c):
    global TARGETS
    nodes = [1]
    print(f'Running on master nodes: {nodes}')
    TARGETS += [hostname(n) for n in nodes]


@task
def nd(c, n):
    global TARGETS
    nodes = [int(n)]
    print(f'Running on nodes: {nodes}')
    TARGETS += [hostname(n) for n in nodes]


@task
def hs(c, hs):
    global TARGETS
    hs = int(hs)
    print(f'Running on hosts: clnode{hs}')
    TARGETS += [f'clnode{hs}.{CLUSTER}.cloudlab.us']


def hostname(node):
    '''Get full hostname for node, 1-based'''
    try:
        node = int(node)
        return f'node-{node}.scaleml.gaia-pg0.{CLUSTER}.cloudlab.us'
    except ValueError:
        return node


def group(*nodes):
    '''Get a group to nodes'''
    # make sure every element is a hostname
    return Group(*[hostname(node) for node in nodes])


def connect(node):
    '''Get a connection to node'''
    return Connection(hostname(node))


def _start_worker(c, task_id, num_worker):
    '''Start a worker on c'''
    cmd = [
        'python',
        '$PROJ_DIR/examples/multiworker.py',
        '--task_id', f'{task_id}',
        '--num_worker', f'{num_worker}',
    ]
    c.run(f'cd $HOME && {" ".join(cmd)}')


@task
def worker(c):
    '''Workers runs on node-{2, 3, 4}'''
    if not TARGETS:
        wk(c)

    for idx, host in enumerate(TARGETS):
        conn = connect(host)
        _start_worker(conn, idx, 5)


@task
def pull(c):
    if not TARGETS:
        ms(c)

    group(*TARGETS).run('cd /nfs/Auto-PyTorch && git pull')
    group(*TARGETS).run('cd /nfs/HpBandSter && git pull')


@task
def conda(c, pkg):
    if not TARGETS:
        all(c)

    group(*TARGETS).run(f'conda install {pkg}')


@task
def pip(c, pkg):
    if not TARGETS:
        all(c)

    group(*TARGETS).run(f'pip install {pkg}')


@task
def rmlog(c):
    if not TARGETS:
        ms(c)

    group(*TARGETS).run('setopt null_glob; rm -f /nfs/log/*.log')


def fuzzy_slug(slug):
    '''Given a slug, find a log_dir'''
    base_dir = TOP_LEVEL / 'log'
    log_dir = base_dir / slug
    if not log_dir.is_dir():
        candidates = [p for p in base_dir.glob(f'*{slug}*') if p.is_dir()]
        if len(candidates) == 1:
            log_dir = candidates[0]
            print(f'Using existing log_dir: {log_dir.name}')
            return log_dir
        elif len(candidates) > 1:
            raise Exit(f'Multiple matches, use more specific name: {candidates}')
        raise Exit(f'Log dir {log_dir} does not exist')
    return log_dir


@task
def log(c, slug=None, glob=None, prep=True):
    try:
        from coolname import generate_slug
    except ImportError:
        raise Exit("Python package `coolname` is needed to generate file name.")

    if not TARGETS:
        ms(c)

    log_dir: Optional[Path] = None
    try:
        if slug is None:
            log_dir = TOP_LEVEL / 'log' / f'{datetime.today().strftime("%Y%m%d")}-{generate_slug(2)}'
            while log_dir.exists():
                log_dir = TOP_LEVEL / 'log' / f'{datetime.today().strftime("%Y%m%d")}-{generate_slug(2)}'

            log_dir.mkdir(parents=True)

            with (log_dir/'.timestamp').open('w') as f:
                print(datetime.now().isoformat(), file=f)
        else:
            log_dir = fuzzy_slug(slug)

        print(f"Downloading to {log_dir}")

        for host in TARGETS:
            if glob is not None:
                c.run(f"rsync -avzzP --info=progress2 '{host}:/nfs/log/*{glob}*.log' {log_dir}/")
            else:
                c.run(f"rsync -avzzP --info=progress2 '{host}:/nfs/log/*.log' {log_dir}/")
    except Failure as e:
        print(e)
        if slug is None and log_dir is not None:
            shutil.rmtree(log_dir)

    if prep:
        preplog(c, log_dir.name)

    print(f"The log_dir is {log_dir.name}")


@task
def preplog(c, slug):
    '''Prepare log to csv'''
    log_dir = fuzzy_slug(slug)

    # remove empty files
    for log_file in log_dir.glob('*.log'):
        if log_file.stat().st_size == 0:
            print(f'Removing empty file {log_file}')
            log_file.unlink()

    # parse legacy format
    tag_with_value = [
        'num_worker',
        'iter',
        'output',
        'name',
    ]
    known_tags = set()
    for log_file in log_dir.glob('*.log'):
        # skip the first 'multiworker' word
        words = log_file.stem.split('-')[1:]
        # words must be an iterator for us to call next in for
        words = iter(words)
        # parse everything into a tag dict
        tags = OrderedDict()
        for word in words:
            if word in tag_with_value:
                try:
                    nword = next(words)
                except StopIteration:
                    raise ValueError(f'Expecting value for {word}')
                tags[word] = nword
            else:
                tags[word] = ''

        # special meaning of 'output' tag, which is used as nodeId
        try:
            node = int(tags.pop('output'))
        except KeyError:
            raise ValueError(f'Unrecognized file name {log_file}, no `output` tag, known tags: {tags}')
        except ValueError:
            raise ValueError(f'Unrecognized file name {log_file}, invalid `output` value, known tags: {tags}')

        # use remaining tags to construct a csv name
        tag_str = '-'.join(word for item in tags.items() for word in item).replace('--', '-').strip('-')
        tgt_csv = log_dir / f'{tag_str}-jobs.csv'
        if tag_str not in known_tags:
            # print header and or remove existing
            if tgt_csv.exists():
                print(f'Removing existing {tgt_csv}')
                tgt_csv.unlink()

            print(f'Generating {tgt_csv.name}')
            with tgt_csv.open('w') as f:
                print('StartTime,EndTime,Iter,Rung,JobId,Budget,Epoches,Node,Tag', file=f)
        known_tags.add(tag_str)

        # actually parse the log file
        print(f'    {log_file.name} -> {tgt_csv.name} [...]', end='')
        try:
            c.run(
                f"rg '(Starting|Finish) optimization for' {log_file}"
                " | "
                f"rg --multiline --only-matching"
                r" '\[([^\]]+)\].*Starting optimization for job \((\d+), (\d+), (\d+)\) with budget (.+)\n"
                r"\[([^\]]+)\].+Finish.+for (\d+) epoches.+\n'"
                fr""" --replace '"$1","$6",$2,$3,$4,$5,$7,{node},{tag_str}'"""
                f" >> {tgt_csv}",
            )
            print('\b\b\b\b\b[Done]')
        except UnexpectedExit:
            print('\b\b\b\b\b[Empty]')

    # parse new event based
    for log_file in log_dir.glob('*.log'):
        tgt_jl = log_file.with_suffix('.jsonl')
        try:
            c.run(
                f"rg --only-matching --pcre2 '(?<=SCHED: ).*$' {log_file}"
                f" > {tgt_jl}"
            )
            print(f'Generating {tgt_jl.name}')
        except UnexpectedExit:
            tgt_jl.unlink()

    compress(c, slug)


@task
def compress(c, slug):
    """Compress log files under folder"""
    import bz2
    print("Now compressing logs")
    orig_sz = 0
    new_sz = 0
    for log_file in fuzzy_slug(slug).glob('*.log'):
        zstd_file = log_file.with_suffix(log_file.suffix + '.bz2')
        with log_file.open('rb') as ifh, bz2.BZ2File(str(zstd_file), 'w') as ofh:
            shutil.copyfileobj(ifh, ofh)
        orig_sz += log_file.stat().st_size
        new_sz += zstd_file.stat().st_size
        log_file.unlink()
    print(f'Reduced {sizeof_fmt(orig_sz - new_sz)} from {sizeof_fmt(orig_sz)} to {sizeof_fmt(new_sz)}')


@task
def extract(c, slug, delete=False):
    """Extract all log files"""
    import bz2
    print("Now uncompressing logs")
    for bz_file in fuzzy_slug(slug).glob('*.log.bz2'):
        log_file = bz_file.with_suffix('')
        with bz2.BZ2File(str(bz_file), 'rb') as ifh, log_file.open('wb') as ofh:
            shutil.copyfileobj(ifh, ofh)
        if delete:
            bz_file.unlink()


@task
def put(c, local, remote):
    '''Upload local to remote path'''
    if not TARGETS:
        all(c)

    for host in TARGETS:
        c = connect(host)
        local = local.format(c=c)
        remote = remote.format(c=c)
        # make sure target dir exist
        home_prefix = "$HOME/"
        if remote and remote[0] == '/':
            home_prefix = ""

        c.run(f'cd $HOME && mkdir -p $(dirname {home_prefix}{remote})')
        c.put(local, remote)


@task
def run(c, cmd, parallel=False):
    '''Run any command'''
    if not TARGETS:
        all(c)

    if not parallel:
        for host in TARGETS:
            c = connect(host)
            c.run(cmd.format(c=c))
    else:
        group(*TARGETS).run(cmd)


r'''
python $PROJ_DIR/examples/basics/multiworker.py --task_id $(hostname | rg -P -o 'node-\K\d') --num_worker 5
'''
