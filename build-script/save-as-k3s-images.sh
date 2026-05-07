#!/bin/bash
docker save $1  | sudo k3s ctr images import -

