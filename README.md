# `ngpus`

> Adapted and modified from https://gitlab.com/Aetf/automl.

A CloudLab profile for a cluster of N GPU nodes, attached to a LAN.
An NFS server provides long-term persistence.

## Details

- Installs CUDA, Docker, and Miniconda3.
- A 200GB block storage is mounted to `/data`, and `/opt` is mounted from `/data/opt`. Docker data root is also set to be `/data/docker-data`.
- An NFS server node (anything available and cheap) is provisioned and connected to all GPUs nodes. 200GB block storage is mounted to `/nfs`.

## Instructions

- For users who were not specified in the experiment startup parameter, run the following to setup your home directory.
    ```bash
    sudo /local/repository/setup-home.sh $USER
    ```
- Run the following to install Jae-Won's dotfiles.
    ```bash
    source <(curl -L https://jaewonchung.me/install-dotfiles.sh)
    ```

## Misc Information

When distributed training collective communication is hanging, consider the following remedies:

- `NCCL_P2P_DISABLE=1`: According to the [NCCL troubleshooting guide](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/troubleshooting.html#pci-access-control-services-acs), P2P can hang because r7525 nodes have PCI ACS enabled.
- `NCCL_SOCKET_IFNAME=ens5f0` and `MASTER_ADDR=192.168.10.1`: This would be using the BlueField SmartNIC for communication between nodes. Note that sometimes, the BF devices in r7525 nodes can be left at a funny state where it is not able to receive and send any data. In that case, reset the NIC following the instructions [here](https://groups.google.com/g/cloudlab-users/c/p04vBvwneN8/m/dXKC6kwSAQAJ).
