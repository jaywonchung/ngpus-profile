"""
A cluster with N nodes attached to a LAN.

Hardware: c6420
Image: UBUNTU18-64-STD
"""

import geni.portal as portal
import geni.rspec.pg as rspec

pc = portal.Context()
pc.defineParameter("num_nodes", "Number of nodes", portal.ParameterType.INTEGER, 5, [])
pc.defineParameter("setup", "name of setup script",
                   portal.ParameterType.STRING, "setup.sh")

request = pc.makeRequestRSpec()
lan = request.LAN("lan")

params = pc.bindParameters()

for i in range(params.num_nodes):
    node = request.RawPC("node-{}".format(i + 1))
    node.disk_image = 'urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU18-64-STD'
    node.hardware_type = "c6420"
    iface = node.addInterface("if1")
    lan.addInterface(iface)
    if len(params.setup) > 0:
        node.addService(rspec.Execute(shell="bash", command="/local/repository/{}".format(params.setup)))

pc.printRequestRSpec(request)
