#!/bin/bash

K3S_MASTER=master
VM_PREF=k3swork
CPU=3
MEM=4G
usage() {
	echo "./multipass_script.sh <machine_count>"
}

create_vm() {
	# delete machines 
	multipass delete --all
	sleep 1
	multipass purge
	sleep 1
	multipass list
	sleep 1
	virsh destroy ${K3S_MASTER}
	sleep 5
	virsh undefine ${K3S_MASTER}
	sleep 1
	for i in $(seq 1 ${1}); do
		virsh destroy ${VM_PREF}${i}
		sleep 5
		virsh undefine ${VM_PREF}${i}
		sleep 1
	done
	echo "ubuntu:ubuntu" > temp_pwd
	# master section
	multipass launch -c ${CPU} -m ${MEM} --name ${K3S_MASTER}
	multipass exec ${K3S_MASTER} sudo chpasswd < temp_pwd
	# worker section
	# create machines and set password 
	for i in $(seq 1 ${1}); do
		multipass launch -c ${CPU} -m ${MEM} --name ${VM_PREF}${i}
		multipass exec ${VM_PREF}${i} sudo chpasswd < temp_pwd
	done
}

deploy_k3s() {
	# deploy k3s to master
	MASTER_IP=$(multipass info ${K3S_MASTER} | egrep IPv4 | awk '{ print $2 }')
	#multipass exec ${K3S_MASTER} -- bash -c " curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=\"--write-kubeconfig ~/.kube/config --write-kubeconfig-mode 666 --tls-san $MASTER_IP --kube-apiserver-arg service-node-port-range=1-65000 --node-external-ip=\"$MASTER_IP\" \" sh - "
	multipass exec ${K3S_MASTER} -- bash -c " curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=\"--write-kubeconfig ~/.kube/config --write-kubeconfig-mode 666  --kube-apiserver-arg service-node-port-range=1-65000 --node-external-ip=\"$MASTER_IP\" \" sh - "
	# get token  and ip
	K3S_TOKEN=$(multipass exec ${K3S_MASTER} sudo cat /var/lib/rancher/k3s/server/node-token)
	#echo ${K3S_TOKEN}
	#echo ${MASTER_IP}
	for i in $(seq 1 ${1}); do
		     multipass exec ${VM_PREF}$i -- bash -c " curl -sfL https://get.k3s.io |  K3S_URL=\"https://${MASTER_IP}:6443\" K3S_TOKEN=\"${K3S_TOKEN}\" sh - "
	done
}

install_istio() {
	multipass exec ${K3S_MASTER} -- bash -c " curl -L https://istio.io/downloadIstio | sh - "
	multipass exec ${K3S_MASTER} -- bash --login -c " cd \$(ls | egrep istio)/bin ; ./istioctl install --set profile=demo -y"
	multipass exec ${K3S_MASTER} -- bash --login -c "kubectl label namespace default istio-injection=enabled"
	multipass exec ${K3S_MASTER} -- bash --login -c "cd \$(ls | egrep istio); kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml"
}

if [[ $# != 1 ]]; then
	usage
	exit
fi

# create vm
create_vm $1
# deploy k3s
deploy_k3s $1
# install istio
install_istio


