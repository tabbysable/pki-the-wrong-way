#! /bin/bash


########################################
# Functions

makeKubeCSR() {
	BASENAME="${1}"
	CN="${2}"
	O="${3}"
	cat > "${BASENAME}.cnf" <<-EOF
		[ req ]
		default_bits = 2048
		default_md = sha256
		prompt = no
		encrypt_key = no
		distinguished_name = dn
		[ dn ]
		O = ${O}
		CN = ${CN}
	EOF
	openssl req -new -config "${BASENAME}.cnf" -keyout "${BASENAME}.key" -out "${BASENAME}.csr"
}
	
########################################
# Setup

# Config
MYDIR=$(mktemp -d /tmp/demo-XXXXXX)
DEMOID=$(echo "${MYDIR}" | sed 's/^.*-//')
export KINDID=$(echo "${DEMOID}" | tr '[[:upper:]]' '[[:lower:]]')

CERTDIR="kubernetes/pki"
ETCDCERTDIR="${CERTDIR}/etcd"

VAULTNAME="demo-vault-${DEMOID}"
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$DEMOID
export VAULT_FORMAT=json

export KUBECONFIG="cluster-admin.kubeconfig"

cd "${MYDIR}"
mkdir -p "${ETCDCERTDIR}"

# Start a vault dev server
docker run --rm -d -p 8200:8200 -e "VAULT_DEV_ROOT_TOKEN_ID=${VAULT_TOKEN}" --name "${VAULTNAME}" vault
sleep 2

# Set up vault RBAC
vault write sys/auth/userpass type=userpass
vault policy write certs - <<EOF
path "pki/*" {
  capabilities = ["create", "update", "read", "list"]
}
EOF
vault write auth/userpass/users/cert-issuer password="password" policies="certs"
vault token create -policy certs -id vault-pki-token -orphan > /dev/null

########################################
# root PKI

vault secrets enable --path pki/root-pki pki
vault secrets tune -max-lease-ttl=$((60*24))h pki/root-pki
vault write pki/root-pki/root/generate/internal common_name=demo-root-ca ttl=$((60*24))h | jq -r '.["data"]["certificate"]' > root.pem
vault write pki/root-pki/roles/super-role max_ttl=24h allow_any_name=true enforce_hostnames=false

########################################
# intermediate PKI

vault secrets enable -path=pki/int-pki pki
vault secrets tune -max-lease-ttl=$((30*24))h pki/int-pki
vault write pki/int-pki/intermediate/generate/internal common_name="demo intermediate PKI" ttl=$((30*24))h | jq -r '.["data"]["csr"]' > int-pki.csr
vault write pki/root-pki/root/sign-intermediate csr=@int-pki.csr format=pem_bundle ttl=$((30*24))h | jq -r '.["data"]["certificate"]' > int-pki.pem
cat root.pem >> int-pki.pem
vault write pki/int-pki/intermediate/set-signed certificate=@int-pki.pem
vault write pki/int-pki/roles/super-role max_ttl=24h allow_any_name=true enforce_hostnames=false


########################################
# etcd leaf PKI

vault secrets enable -path=pki/etcd-pki pki
vault secrets tune -max-lease-ttl=$((30*24))h pki/etcd-pki
vault write pki/etcd-pki/intermediate/generate/internal common_name="demo etcd PKI" ttl=$((30*24))h | jq -r '.["data"]["csr"]' > etcd-pki.csr
vault write pki/int-pki/root/sign-intermediate csr=@etcd-pki.csr format=pem_bundle ttl=$((30*24))h | jq -r '.["data"]["certificate"]' > etcd-pki.pem
vault write pki/etcd-pki/intermediate/set-signed certificate=@etcd-pki.pem
vault write pki/etcd-pki/roles/super-role max_ttl=24h allow_any_name=true enforce_hostnames=false


########################################
# k8s leaf PKI

vault secrets enable -path=pki/k8s-pki pki
vault secrets tune -max-lease-ttl=$((30*24))h pki/k8s-pki
json=$(vault write pki/k8s-pki/intermediate/generate/exported common_name="demo k8s PKI" ttl=$((30*24))h)
echo $json | jq -r '.["data"]["csr"]' > k8s-pki.csr
echo $json | jq -r '.["data"]["private_key"]' > k8s-pki.key
vault write pki/int-pki/root/sign-intermediate csr=@k8s-pki.csr format=pem_bundle ttl=$((30*24))h | jq -r '.["data"]["certificate"]' > k8s-pki.pem
vault write pki/k8s-pki/intermediate/set-signed certificate=@k8s-pki.pem
vault write pki/k8s-pki/roles/super-role max_ttl=24h allow_any_name=true enforce_hostnames=false


########################################
# nonprod k8s leaf PKI

vault secrets enable -path=pki/nonprod-k8s-pki pki
vault secrets tune -max-lease-ttl=$((30*24))h pki/nonprod-k8s-pki
json=$(vault write pki/nonprod-k8s-pki/intermediate/generate/exported common_name="demo nonprod-k8s PKI" ttl=$((30*24))h)
echo $json | jq -r '.["data"]["csr"]' > nonprod-k8s-pki.csr
echo $json | jq -r '.["data"]["private_key"]' > nonprod-k8s-pki.key
vault write pki/int-pki/root/sign-intermediate csr=@nonprod-k8s-pki.csr format=pem_bundle ttl=$((30*24))h | jq -r '.["data"]["certificate"]' > nonprod-k8s-pki.pem
vault write pki/nonprod-k8s-pki/intermediate/set-signed certificate=@nonprod-k8s-pki.pem
vault write pki/nonprod-k8s-pki/roles/super-role max_ttl=24h allow_any_name=true enforce_hostnames=false


########################################
# front-proxy leaf PKI

vault secrets enable -path=pki/front-proxy-pki pki
vault secrets tune -max-lease-ttl=$((30*24))h pki/front-proxy-pki
vault write pki/front-proxy-pki/intermediate/generate/internal common_name="demo front-proxy PKI" ttl=$((30*24))h | jq -r '.["data"]["csr"]' > front-proxy-pki.csr
vault write pki/int-pki/root/sign-intermediate csr=@front-proxy-pki.csr format=pem_bundle ttl=$((30*24))h | jq -r '.["data"]["certificate"]' > front-proxy-pki.pem
vault write pki/front-proxy-pki/intermediate/set-signed certificate=@front-proxy-pki.pem
vault write pki/front-proxy-pki/roles/super-role max_ttl=24h allow_any_name=true enforce_hostnames=false


########################################
# example.net leaf PKI

vault secrets enable -path=pki/example-net-pki pki
vault secrets tune -max-lease-ttl=$((30*24))h pki/example-net-pki
vault write pki/example-net-pki/intermediate/generate/internal common_name="demo example-net PKI" ttl=$((30*24))h | jq -r '.["data"]["csr"]' > example-net-pki.csr
vault write pki/int-pki/root/sign-intermediate csr=@example-net-pki.csr format=pem_bundle ttl=$((30*24))h | jq -r '.["data"]["certificate"]' > example-net-pki.pem
vault write pki/example-net-pki/intermediate/set-signed certificate=@example-net-pki.pem
vault write pki/example-net-pki/roles/example-net allowed_domains=example.net allow_subdomains=true max_ttl=24h 
vault write pki/example-net-pki/roles/server-example-net allowed_domains=example.net allow_subdomains=true max_ttl=24h client_flag=false


########################################
# apiserver-etcd-client cert

makeKubeCSR "${CERTDIR}/apiserver-etcd-client" kube-apiserver-etcd-client system:masters
# fixme
#json=$(vault write pki/etcd-pki/sign-verbatim csr=@"${CERTDIR}/apiserver-etcd-client.csr" ttl=24h)
json=$(vault write pki/k8s-pki/sign-verbatim csr=@"${CERTDIR}/apiserver-etcd-client.csr" ttl=24h)
echo "${json}" | jq -r '.["data"]["certificate"],.["data"]["ca_chain"][]' > "${CERTDIR}/apiserver-etcd-client.crt"


########################################
# apiserver-kubelet-client cert

makeKubeCSR "${CERTDIR}/apiserver-kubelet-client" kube-apiserver-kubelet-client system:masters
json=$(vault write pki/k8s-pki/sign-verbatim csr=@"${CERTDIR}/apiserver-kubelet-client.csr" ttl=24h)
echo "${json}" | jq -r '.["data"]["certificate"],.["data"]["ca_chain"][]' > "${CERTDIR}/apiserver-kubelet-client.crt"


########################################
# apiserver cert

json=$(vault write pki/k8s-pki/issue/super-role common_name="kube-apiserver" alt_names="kind-${KINDID}-control-plane,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster.local,localhost" ip_sans="$(for ((i=2;i<255;i++)); do echo -n 172.18.0.$i,; done)10.96.0.1,127.0.0.1" exclude_cn_from_sans=true ttl=24h)
echo "${json}" | jq -r '.["data"]["certificate"],.["data"]["ca_chain"][]' > "${CERTDIR}/apiserver.crt"
echo "${json}" | jq -r '.["data"]["private_key"]' > "${CERTDIR}/apiserver.key"


########################################
# k8s ca cert

cp k8s-pki.pem "${CERTDIR}/ca.crt"
vault read pki/k8s-pki/cert/ca | jq -r '.["data"]["certificate"]' > "${CERTDIR}/ca-signing.crt"
cp k8s-pki.key "${CERTDIR}/ca.key"


########################################
# etcd ca cert

# fixme
#cp etcd-pki.pem "${ETCDCERTDIR}/ca.crt"
cp k8s-pki.pem "${ETCDCERTDIR}/ca.crt"


########################################
# etcd healthcheck-client cert

makeKubeCSR "${ETCDCERTDIR}/healthcheck-client" kube-etcd-healthcheck-client system:masters
# fixme
#json=$(vault write pki/etcd-pki/sign-verbatim csr=@"${ETCDCERTDIR}/healthcheck-client.csr" ttl=24h)
json=$(vault write pki/k8s-pki/sign-verbatim csr=@"${ETCDCERTDIR}/healthcheck-client.csr" ttl=24h)
echo "${json}" | jq -r '.["data"]["certificate"],.["data"]["ca_chain"][]' > "${ETCDCERTDIR}/healthcheck-client.crt"


########################################
# etcd peer cert

# fixme
#json=$(vault write pki/etcd-pki/issue/super-role common_name="kind-control-plane" alt_names="localhost" ip_sans="127.0.0.1" ttl=24h)
json=$(vault write pki/k8s-pki/issue/super-role common_name="kind-control-plane" alt_names="localhost" ip_sans="127.0.0.1" ttl=24h)
echo "${json}" | jq -r '.["data"]["certificate"],.["data"]["ca_chain"][]' > "${ETCDCERTDIR}/peer.crt"
echo "${json}" | jq -r '.["data"]["private_key"]' > "${ETCDCERTDIR}/peer.key"


########################################
# etcd server cert

# fixme
#json=$(vault write pki/etcd-pki/issue/super-role common_name="kind-control-plane" alt_names="localhost" ip_sans="127.0.0.1" ttl=24h)
json=$(vault write pki/k8s-pki/issue/super-role common_name="kind-control-plane" alt_names="localhost" ip_sans="127.0.0.1" ttl=24h)
echo "${json}" | jq -r '.["data"]["certificate"],.["data"]["ca_chain"][]' > "${ETCDCERTDIR}/server.crt"
echo "${json}" | jq -r '.["data"]["private_key"]' > "${ETCDCERTDIR}/server.key"


########################################
# front-proxy ca cert

# fixme
#cp front-proxy-pki.pem "${CERTDIR}/front-proxy-ca.crt"
cp k8s-pki.pem "${CERTDIR}/front-proxy-ca.crt"


########################################
# front-proxy client cert

# fixme
#json=$(vault write pki/front-proxy-pki/issue/super-role common_name="front-proxy-client" ttl=24h)
json=$(vault write pki/k8s-pki/issue/super-role common_name="front-proxy-client" ttl=24h)
echo "${json}" | jq -r '.["data"]["certificate"],.["data"]["ca_chain"][]' > "${CERTDIR}/front-proxy-client.crt"
echo "${json}" | jq -r '.["data"]["private_key"]' > "${CERTDIR}/front-proxy-client.key"


########################################
# nonprod k8s admin cert

makeKubeCSR "nonprod-k8s-admin" goose system:masters
json=$(vault write pki/nonprod-k8s-pki/sign-verbatim csr=@"nonprod-k8s-admin.csr" ttl=24h)
echo "${json}" | jq -r '.["data"]["certificate"],.["data"]["ca_chain"][]' > "nonprod-k8s-admin.crt"


########################################
# k8s low-priv client cert

makeKubeCSR "k8s-client" tabby CaTS
json=$(vault write pki/k8s-pki/sign-verbatim csr=@"k8s-client.csr" ttl=24h)
echo "${json}" | jq -r '.["data"]["certificate"],.["data"]["ca_chain"][]' > "k8s-client.crt"


########################################
# Start cluster

cat > cluster.yaml <<-EOF
	kind: Cluster
	apiVersion: kind.x-k8s.io/v1alpha4
	nodes:
	- role: control-plane
	  extraMounts:
	  - hostPath: ${MYDIR}/kubernetes/pki
	    containerPath: /etc/kubernetes/pki
	EOF


# hack the kube-controller-manager configuration while kind is running
sleep 20 && docker exec "kind-${KINDID}-control-plane" sed -i '/cluster-signing-cert-file/ s/ca.crt/ca-signing.crt/' /etc/kubernetes/manifests/kube-controller-manager.yaml &

# fixme
# hack the kube-apiserver configuration while kind is running
sleep 20 && docker exec "kind-${KINDID}-control-plane" sed -i '/requestheader-allowed-names/ s/=.*$/=/' /etc/kubernetes/manifests/kube-apiserver.yaml &

kind create cluster --name "kind-${KINDID}" --config cluster.yaml --wait 3m

########################################
# Prep kubeconfig files

kubectl config use-context "kind-kind-${KINDID}"
sed -i "s/kind-kind-${KINDID}\$/default/" "${KUBECONFIG}"

# k8s user-level kubeconfig
cp "${KUBECONFIG}" k8s-client.kubeconfig
clientcert=$(base64 -w 0 < k8s-client.crt)
sed -i "s/client-certificate-data: .*\$/client-certificate-data: ${clientcert}/" k8s-client.kubeconfig
clientkey=$(base64 -w 0 < k8s-client.key)
sed -i "s/client-key-data: .*\$/client-key-data: ${clientkey}/" k8s-client.kubeconfig
unset clientcert clientkey

# nonprod k8s admin kubeconfig
cp "${KUBECONFIG}" nonprod-k8s-admin.kubeconfig
clientcert=$(base64 -w 0 < nonprod-k8s-admin.crt)
sed -i "s/client-certificate-data: .*\$/client-certificate-data: ${clientcert}/" nonprod-k8s-admin.kubeconfig
clientkey=$(base64 -w 0 < nonprod-k8s-admin.key)
sed -i "s/client-key-data: .*\$/client-key-data: ${clientkey}/" nonprod-k8s-admin.kubeconfig
unset clientcert clientkey

########################################
# Configure cluster

# Prep webserver setup script into base64
setupsh=`base64 -w 0 <<"EOF"
#! /bin/bash
export DEBIAN_FRONTEND=noninteractive
export VAULT_FORMAT=json
sleep 10
apt update
apt install -y nginx curl openssl unzip jq
[ $? -ne 0 ] && exit 1
curl -s https://releases.hashicorp.com/vault/1.5.4/vault_1.5.4_linux_amd64.zip | funzip > /usr/local/bin/vault
chmod 755 /usr/local/bin/vault
ln -s /root/vault-token/vault-token /root/.vault-token
# fixme
#json=$(vault write pki/example-net-pki/issue/server-example-net common_name="www.example.net" ttl=24h)
json=$(vault write pki/example-net-pki/issue/example-net common_name="www.example.net" ttl=24h)
echo "${json}" | jq -r '.["data"]["certificate"],.["data"]["ca_chain"][]' > "/etc/ssl/certs/webserver.pem"
echo "${json}" | jq -r '.["data"]["private_key"]' > "/etc/ssl/private/webserver.key"
unset json
ln -fs ../my-sites/default /etc/nginx/sites-enabled/default
nginx
sleep 3600
EOF
`

# YOLO some YAML into the cluster
kubectl apply -f - <<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: CaTS
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: admin
subjects:
  - kind: Group
    name: CaTS
    namespace: default
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-token
  namespace: default
type: Opaque
data:
  vault-token: $(echo -n vault-pki-token | base64)
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: setup-script
  namespace: default
binaryData:
  setup.sh: ${setupsh}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: default
data:
  default: |
    server {
            listen 80 default_server;
            listen 443 ssl default_server;
            ssl_certificate /etc/ssl/certs/webserver.pem;
            ssl_certificate_key /etc/ssl/private/webserver.key;
            root /var/www/html;
            index index.html index.htm index.nginx-debian.html;
            server_name _;
    }
---
apiVersion: v1
kind: Service
metadata:
  name: webserver
  labels:
    app: webserver
  namespace: default
spec:
  type: NodePort
  externalTrafficPolicy: Local
  ports:
  - port: 4443
    targetPort: https
    protocol: TCP
    nodePort: 30000
    name: webserver
  selector:
    app: webserver
---
apiVersion: v1
kind: Pod
metadata:
  name: webserver
  namespace: default
  labels:
    app: webserver
spec:
  containers:
    - name: webserver
      image: ubuntu:20.04
      command: ["/bin/bash","/setup/setup.sh"]
      ports:
      - name: https
        containerPort: 443
        protocol: TCP
      volumeMounts:
      - name: setup
        mountPath: "/setup"
        readOnly: true
      - name: vault-token
        mountPath: "/root/vault-token"
        readOnly: true
      - name: nginx-config
        mountPath: "/etc/nginx/my-sites"
        readOnly: true
      env:
      - name: VAULT_ADDR
        value: "http://172.17.0.1:8200"
  volumes:
    - name: vault-token
      secret:
        secretName: vault-token
    - name: setup
      configMap:
        name: setup-script
        items:
        - key: "setup.sh"
          path: "setup.sh"
    - name: nginx-config
      configMap:
        name: nginx-config
        items:
        - key: "default"
          path: "default"
---
EOF


########################################
# Wrapup

# drop to a shell for further messing-about
echo "This shell configured to use the demo vault server:"
bash -i

echo -e "#to cleanup: \ndocker stop \"${VAULTNAME}\" && kind delete cluster --name kind-${KINDID} && rm -rf \"${MYDIR}\""
