from datetime import datetime
from pathlib import Path

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


@task
def log(c):
    try:
        from coolname import generate_slug
    except ImportError:
        raise Exit("Python package `coolname` is needed to generate file name.")

    if not NODES:
        ms(c)

    log_dir = TOP_LEVEL / 'log' / generate_slug(2)
    while log_dir.exists():
        log_dir = TOP_LEVEL / 'log' / generate_slug(2)

    log_dir.mkdir(parents=True)

    with (log_dir/'.timestamp').open('w') as f:
        print(datetime.now().isoformat(), file=f)

    for node in NODES:
        c.run(f"rsync '{hostname(node)}:/nfs/log/*' {log_dir}/")

    print(f"Log downloaded to {log_dir}")


@task
def preplog(c, slug):
    '''Prepare log to csv'''
    base_dir = TOP_LEVEL / 'log'
    log_dir = base_dir / slug
    if not log_dir.is_dir():
        # try prefix match
        for log_dir in base_dir.glob(f'{slug}*'):
            if log_dir.is_dir():
                break
            raise Exit(f'Log dir {log_dir} does not exist')

    # remove empty files
    for log_file in log_dir.glob('*.log'):
        if log_file.stat().st_size == 0:
            print(f'Removing empty file {log_file}')
            log_file.unlink()

    # find if all different num_worker (as tag)
    tags = []
    for log_file in log_dir.glob('*.log'):
        tag = '-'.join(log_file.stem.split('-')[:-2])
        tags.append(tag)
    tags = set(tags)

    for tag in tags:
        tgt_csv = log_dir / f'{tag}-jobs.csv'
        if tgt_csv.exists():
            print(f'Removing existing {tgt_csv}')
            tgt_csv.unlink()

        with tgt_csv.open('w') as f:
            print('StartTime,EndTime,Iter,JobId,Budget,Epoches,Node', file=f)

    for tag in tags:
        # extract start/finish for different num_worker
        tgt_csv = log_dir / f'{tag}-jobs.csv'
        for log_file in log_dir.glob(f'{tag}-*.log'):
            node = int(log_file.stem.split('-')[-1])
            c.run(
                f"rg '(Starting|Finish) optimization for' {log_file}"
                " | "
                f"rg --multiline --only-matching"
                r" '\[([^\]]+)\].*Starting optimization for job \((\d+), \d+, (\d+)\) with budget (.+)\n"
                r"\[([^\]]+)\].+Finish.+for (\d+) epoches.+\n'"
                fr""" --replace '"$1","$5",$2,$3,$4,$6,{node}'"""
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
