"""A cluster of N GPU nodes, attached to a LAN. An NFS server provides long-term persistency.

Instructions:

Wait for the setup script to finish. Then GPU nodes will reboot in order to load their NVIDIA drivers. After reboot, you may login. A 200GB block storage is mounted to `/data`, and `/opt` is mounted from `/data/opt`. So install large software packages inside `/opt`. To use Jae-Won's dotfiles, run `source <(curl https://jaewonchung.me/install-dotfiles.sh)`. Then install miniconda3 with `CONDA_PREFIX=/opt/miniconda3 bash ~/.dotmodules/inventory/miniconda.sh`.
"""

import geni.portal as portal
import geni.rspec.pg as rspec

# Only Ubuntu images supported.
imageList = [
    ('urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU20-64-STD', 'UBUNTU 20.04'),
    ('urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU18-64-STD', 'UBUNTU 18.04'),
]

pc = portal.Context()
pc.defineParameter("num_nodes", "Number of nodes", portal.ParameterType.INTEGER, 1)
pc.defineParameter("user_name", "Username", portal.ParameterType.STRING, "jwnchung")
pc.defineParameter("project_group_name", "Project group name", portal.ParameterType.STRING, "gaia-PG0")
pc.defineParameter("os_image", "OS image", portal.ParameterType.IMAGE, imageList[0], imageList)
pc.defineParameter("node_hw", "GPU Node type", portal.ParameterType.NODETYPE, "r7525")
pc.defineParameter("nfs_hw", "NFS node type", portal.ParameterType.NODETYPE, "c8220")
pc.defineParameter("dataset", "Dataset URN backing the NFS storage, leave empty to use an ephermal 200G blockstorage on the nfs server", portal.ParameterType.STRING, "", advanced=True)
params = pc.bindParameters()

request = pc.makeRequestRSpec()

# add lan
lan = request.LAN("nfsLan")
lan.best_effort = True
lan.vlan_tagging = True
lan.link_multiplexing = True

# nfs server with special block storage server
nfsServer = request.RawPC("nfs")
nfsServer.disk_image = params.os_image
nfsServer.hardware_type = params.nfs_hw
nfsServerInterface = nfsServer.addInterface()
nfsServerInterface.addAddress(rspec.IPv4Address("192.168.1.250", "255.255.255.0"))
lan.addInterface(nfsServerInterface)
nfsServer.addService(rspec.Execute(shell="bash", command="/local/repository/setup-firewall.sh"))
nfsServer.addService(rspec.Execute(shell="bash", command="/local/repository/nfs-server.sh"))

# Special node that represents the ISCSI device where the dataset resides
nfsDirectory = "/nfs"
if params.dataset:
    dsnode = request.RemoteBlockstore("dsnode", nfsDirectory)
    dsnode.dataset = params.dataset
    dslink = request.Link("dslink")
    dslink.addInterface(dsnode.interface)
    dslink.addInterface(nfsServer.addInterface())
    # Special attributes for this link that we must use.
    dslink.best_effort = True
    dslink.vlan_tagging = True
    dslink.link_multiplexing = True
else:
    bs = nfsServer.Blockstore("nfs-bs", nfsDirectory)
    bs.size = "200GB"

# normal nodes
for i in range(params.num_nodes):
    node = request.RawPC("node-{}".format(i + 1))
    node.disk_image = params.os_image
    node.hardware_type = params.node_hw
    bs = node.Blockstore("bs-{}".format(i + 1), "/data")
    bs.size = "200GB"
    intf = node.addInterface("if1")
    if node.hardware_type == "r7525":
        # r7525 requires special config to use its normal 25Gbps experimental network
        intf.bandwidth = 25600
    intf.addAddress(rspec.IPv4Address("192.168.1.{}".format(i + 1), "255.255.255.0"))
    lan.addInterface(intf)
    node.addService(rspec.Execute(shell="bash", command="/local/repository/setup-firewall.sh"))
    node.addService(rspec.Execute(shell="bash", command="/local/repository/nfs-client.sh"))
    node.addService(
        rspec.Execute(
            shell="bash",
            command="/local/repository/setup-node.sh {} {}".format(params.user_name, params.project_group_name)
        )
    )

pc.printRequestRSpec(request)
