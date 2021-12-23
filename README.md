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
    source <(curl https://jaewonchung.me/install-dotfiles.sh)
    ```
