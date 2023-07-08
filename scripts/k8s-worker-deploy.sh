#!/bin/bash

prog_name=`basename "$0"`
Help ()
{
    if [ -z "$help_printed" ]; then
        echo 'Deploy kubernetes on a worker node and make it join a cluster'
        echo
        echo "Syntax: $prog_name [--help|-h] [--master <master-address> --token <token> --discovery-token-ca-cert-hash <ca-cert-hash>]"
        echo "options:"
        echo "--master                          The address of the master node in <hostname>:<port> that can be used in 'kubeadm join' command"
        echo "--token                           The token that should be used in 'kubeadm join' command"
        echo "--discovery-token-ca-cert-hash    The discovery-token-ca-cert-hash should be used in 'kubeadm join' command"
        echo "--help|-h                         Print this help message"
        help_printed=true
    fi
}

Error ()
{
    if [ -z "$help_printed" ]; then
        echo "$1" >&2
        Help
    fi
    exit 1
}

optspec=":h-:"
while getopts "$optspec" optchar; do
    case "${optchar}" in
        -)
            case "${OPTARG}" in
                master)
                    master="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    ;;
                master=*)
                    master=${OPTARG#*=}
                    ;;
                token)
                    token="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    ;;
                token=*)
                    token=${OPTARG#*=}
                    ;;
                discovery-token-ca-cert-hash)
                    ca_cert_hash="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    ;;
                discovery-token-ca-cert-hash=*)
                    ca_cert_hash=${OPTARG#*=}
                    ;;
                help)
                    Help
                    ;;
                *=*)
                    val=${OPTARG#*=}
                    opt=${OPTARG%=$val}
                    echo "Unknown long option --${opt}" >&2
                    Error
                    ;;
                *)
                    echo "Unknown long option --${OPTARG}" >&2
                    Error
                    ;;
            esac
            ;;
        h)
            Help
            ;;
        *)
            if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
                echo "Unrecognized option argument: '-${OPTARG}'" >&2
                Error
            fi
            ;;
    esac
done
if [ -z "$master" ]; then
    Error "--master option is not set"
fi
if [ -z "$token" ]; then
    Error "--token option is not set"
fi
if [ -z "$ca_cert_hash" ]; then
    Error "--discovery-token-ca-cert-hash option is not set"
fi
echo "master = ${master}, token = ${token}, ca_cert_hash = ${ca_cert_hash}"

sudo apt update -y
sudo apt upgrade -y
sudo swapon --show
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu  jammy stable"
sudo apt update
sudo apt install -y containerd.io
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/kubernetes-xenial.gpg
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo kubeadm join ${master} --token ${token} --discovery-token-ca-cert-hash ${ca_cert_hash}
