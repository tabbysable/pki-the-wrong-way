# pki-the-wrong-way
Scripting and notes from KubeCon NA 2020 presentation "PKI the Wrong Way"

Most of the misconfigurations exploited in this demo have corrections in `demosetup.sh` and are marked with `# fixme` for ease of finding.
## Requirements

I've been running this on Ubuntu 20.04.

Offhand, you'll need to install the following tools in addition to the usual Ubuntu stuff:

* docker
* vault
* jq
* kind
* kubectl
* etcdctl

