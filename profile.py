"""
A cluster with N nodes attached to a LAN. With a NFS server and dataset long-term persistancy.

Hardware: c6420
Image: UBUNTU18-64-STD
"""

import geni.portal as portal
import geni.rspec.pg as rspec

# Only Ubuntu images supported.
imageList = [
    ('urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU18-64-STD', 'UBUNTU 18.04'),
    ('urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU16-64-STD', 'UBUNTU 16.04'),
    ('urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU14-64-STD', 'UBUNTU 14.04'),
    ('urn:publicid:IDN+emulab.net+image+emulab-ops//CENTOS7-64-STD', 'CENTOS 7'),
]

pc = portal.Context()
pc.defineParameter("num_nodes", "Number of nodes", portal.ParameterType.INTEGER, 5, [])
pc.defineParameter("user_name", "user name to run additional setup script",
                   portal.ParameterType.STRING, "peifeng")
pc.defineParameter("setup", "additional setup script",
                   portal.ParameterType.STRING, "setup.sh")
pc.defineParameter("os_image", "Select OS image",
                   portal.ParameterType.IMAGE,
                   imageList[0], imageList, advanced=True)
pc.defineParameter("dataset", "Dataset backing the NFS storage",
                   portal.ParameterType.STRING,
                   "urn:publicid:IDN+clemson.cloudlab.us:gaia-pg0+ltdataset+automl", advanced=True)
params = pc.bindParameters()

# Do not change these unless you change the setup scripts too.
nfsServerName = "nfs"
nfsLanName = "nfsLan"
nfsDirectory = "/nfs"

request = pc.makeRequestRSpec()

# add lan
lan = request.LAN(nfsLanName)
lan.best_effort = True
lan.vlan_tagging = True
lan.link_multiplexing = True

# nfs server with special block storage server
nfsServer = request.RawPC(nfsServerName)
nfsServer.disk_image = params.os_image
lan.addInterface(nfsServer.addInterface())
nfsServer.addService(rspec.Execute(shell="bash", command="/local/repository/nfs-server.sh"))

# Special node that represents the ISCSI device where the dataset resides
dsnode = request.RemoteBlockstore("dsnode", nfsDirectory)
dsnode.dataset = params.dataset
dslink = request.Link("dslink")
dslink.addInterface(dsnode.interface)
dslink.addInterface(nfsServer.addInterface())
# Special attributes for this link that we must use.
dslink.best_effort = True
dslink.vlan_tagging = True
dslink.link_multiplexing = True

# normal nodes
for i in range(params.num_nodes):
    node = request.RawPC("node-{}".format(i + 1))
    node.disk_image = params.os_image
    node.hardware_type = "c6420"
    lan.addInterface(node.addInterface("if1"))
    node.addService(rspec.Execute(shell="bash", command="/local/repository/nfs-client.sh"))
    if len(params.setup) > 0:
        node.addService(rspec.Execute(shell="bash",
                                      command="/local/repository/{} {}".format(params.setup, params.user_name)))

pc.printRequestRSpec(request)
