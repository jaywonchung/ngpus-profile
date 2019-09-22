from datetime import datetime
from pathlib import Path

from invoke import task
from fabric import Connection, ThreadingGroup as Group

CLUSTERS = {
    'clemson': 'clnode{}'
}
CLUSTER = 'clemson'
HOSTS = (
    216,
    205,
    188,
    193,
    213
)

# will be modified by host selector tasks
NODES = []


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
def rmlog(c):
    if not NODES:
        all(c)

    group(*NODES).run('setopt null_glob; rm -f /nfs/log/multiworker-*.log')


@task
def log(c):
    if not NODES:
        ms(c)

    log_dir = Path(f'log/{datetime.now().isoformat()}')
    log_dir.mkdir(parents=True)

    for node in NODES:
        c.run(f"rsync '{hostname(node)}:/nfs/log/*' {log_dir}/")


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
def run(c, cmd):
    '''Run any command'''
    if not NODES:
        all(c)

    for node in NODES:
        c = connect(node)
        c.run(cmd.format(c=c))


r'''
python $PROJ_DIR/examples/basics/multiworker.py --task_id $(hostname | rg -P -o 'node-\K\d') --num_worker 5
'''
