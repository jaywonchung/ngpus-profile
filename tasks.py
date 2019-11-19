from datetime import datetime
from pathlib import Path
from collections import OrderedDict

from invoke import task
from invoke.exceptions import Exit
from fabric import Connection, ThreadingGroup as Group

CLUSTERS = {
    'clemson': 'clnode{}'
}
CLUSTER = 'clemson'
HOSTS = [
    185,
    202,
    190,
    211,
    201,
    194,
]

# will be modified by host selector tasks
NODES = []

# Top level dir
TOP_LEVEL = Path(__file__).parent


@task
def all(c):
    global NODES
    NODES += [1, 2, 3, 4, 5]
    print(f'Running on all nodes: {NODES}')


@task
def wk(c):
    global NODES
    NODES += [2, 3, 4, 5]
    print(f'Running on worker nodes: {NODES}')


@task
def ms(c):
    global NODES
    NODES += [1]
    print(f'Running on master nodes: {NODES}')


@task
def nd(c, n):
    global NODES
    NODES += [int(n)]
    print(f'Running on nodes: {NODES}')


@task
def hs(c, hs):
    global NODES
    global HOSTS

    HOSTS += [int(hs)]
    NODES += [len(HOSTS)]
    print(f'Running no hosts: clnode{HOSTS[-1]}')


def hostname(node):
    '''Get full hostname for node, 1-based'''
    return CLUSTERS[CLUSTER].format(HOSTS[node - 1])


def group(*nodes):
    '''Get a group to nodes'''
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
    if not NODES:
        wk(c)

    for node in NODES:
        conn = connect(node)
        _start_worker(conn, node, 5)


@task
def pull(c):
    if not NODES:
        ms(c)

    group(*NODES).run('cd $PROJ_DIR && git pull')


@task
def pip(c, pkg):
    if not NODES:
        all(c)

    group(*NODES).run(f'pip install {pkg}')


@task
def rmlog(c):
    if not NODES:
        ms(c)

    group(*NODES).run('setopt null_glob; rm -f /nfs/log/*.log')


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

    if not NODES:
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

    for node in NODES:
        c.run(f"rsync '{hostname(node)}:/nfs/log/*' {log_dir}/")

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
    if not NODES:
        all(c)

    for node in NODES:
        c = connect(node)
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
    if not NODES:
        all(c)

    if not parallel:
        for node in NODES:
            c = connect(node)
            c.run(cmd.format(c=c))
    else:
        group(*NODES).run(cmd)


r'''
python $PROJ_DIR/examples/basics/multiworker.py --task_id $(hostname | rg -P -o 'node-\K\d') --num_worker 5
'''
