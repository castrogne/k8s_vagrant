#!/bin/bash

KUBE_VERSION="1.26.3-00"

# Disable swap
usermod -aG docker vagrant
swapoff -a
