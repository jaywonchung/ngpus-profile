from datetime import datetime
from pathlib import Path
from collections import OrderedDict

from invoke import task
from invoke.exceptions import Exit
from fabric import Connection, ThreadingGroup as Group

CLUSTER = 'clemson'

# will be modified by host selector tasks
TARGETS = []

# Top level dir
TOP_LEVEL = Path(__file__).parent


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

    group(*TARGETS).run('cd $PROJ_DIR && git pull')


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
        # try prefix match
        for log_dir in base_dir.glob(f'{slug}*'):
            if log_dir.is_dir():
                print(f'Using existing log_dir: {log_dir.name}')
                return log_dir
    raise Exit(f'Log dir {log_dir} does not exist')


@task
def log(c, slug=None):
    try:
        from coolname import generate_slug
    except ImportError:
        raise Exit("Python package `coolname` is needed to generate file name.")

    if not TARGETS:
        ms(c)

    if slug is None:
        log_dir = TOP_LEVEL / 'log' / generate_slug(2)
        while log_dir.exists():
            log_dir = TOP_LEVEL / 'log' / generate_slug(2)

        log_dir.mkdir(parents=True)

        with (log_dir/'.timestamp').open('w') as f:
            print(datetime.now().isoformat(), file=f)
    else:
        log_dir = fuzzy_slug(slug)

    for host in TARGETS:
        c.run(f"rsync '{host}:/nfs/log/*' {log_dir}/")

    print(f"Log downloaded to {log_dir}")


@task
def preplog(c, slug):
    '''Prepare log to csv'''
    log_dir = fuzzy_slug(slug)

    # remove empty files
    for log_file in log_dir.glob('*.log'):
        if log_file.stat().st_size == 0:
            print(f'Removing empty file {log_file}')
            log_file.unlink()

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
                print('StartTime,EndTime,Iter,JobId,Budget,Epoches,Node,Tag', file=f)
        known_tags.add(tag_str)

        # actually parse the log file
        c.run(
            f"rg '(Starting|Finish) optimization for' {log_file}"
            " | "
            f"rg --multiline --only-matching"
            r" '\[([^\]]+)\].*Starting optimization for job \((\d+), \d+, (\d+)\) with budget (.+)\n"
            r"\[([^\]]+)\].+Finish.+for (\d+) epoches.+\n'"
            fr""" --replace '"$1","$5",$2,$3,$4,$6,{node},{tag_str}'"""
            f" >> {tgt_csv}",
        )


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
