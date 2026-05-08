#!/bin/bash
docker save $1  | sudo k3s ctr -n k8s.io images import -

