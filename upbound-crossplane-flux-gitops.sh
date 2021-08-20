# Source: https://gist.github.com/8445ee77f7c4a4eb5c8001b10e86b271

##############################################################
# Applying GitOps On Infrastructure With Flux And Crossplane #
##############################################################

# References:
# - Upbound docs: https://cloud.upbound.io/docs/
# - Crossplane docs: https://crossplane.io/docs
# - Flux: https://youtu.be/R6OeIgb7lUI
# - Upbound: https://youtu.be/jyv0SBXoVXA
# - Crossplane: https://youtu.be/yrj4lmScKHQ
# - Crossplane composites: https://youtu.be/AtbS1u2j7po
# - K3d: https://youtu.be/mCesuGk-Fks
# - GitHub CLI: https://youtu.be/BII6ZY2Rnlc

#########
# Setup #
#########

git clone \
    https://github.com/vfarcic/crossplane-flux-infra

cd crossplane-flux-infra

# Replace `[...]` with the GitHub organization or user
export GITHUB_ORG=[...]

# Replace `[...]` with the GitHub token
export GITHUB_TOKEN=[...]

# Replace `[...]` with `true` if it is a personal account, or with `false` if it is an GitHub organization
export GITHUB_PERSONAL=[...]

# Replace `[...]` with your access key ID`
export AWS_ACCESS_KEY_ID=[...]

# Replace `[...]` with your secret access key
export AWS_SECRET_ACCESS_KEY=[...]

# Please watch https://youtu.be/mCesuGk-Fks if you are not familiar with k3d
# Feel free to use any other Kubernetes platform
k3d cluster create --config k3d.yaml

cd ..

# https://fluxcd.io/docs/get-started/#install-the-flux-cli

######################
# Bootstrapping Flux #
######################

flux bootstrap github \
    --owner $GITHUB_ORG \
    --repository crossplane-flux \
    --branch main \
    --path infra \
    --personal $GITHUB_PERSONAL

git clone \
    https://github.com/$GITHUB_ORG/crossplane-flux

cd crossplane-flux

ls -1 infra

ls -1 infra/flux-system

#################################
# Installing Upbound Crossplane #
#################################

flux create source helm upbound \
    --interval 1h \
    --url https://charts.upbound.io/stable \
    --export \
    | tee infra/upbound-source.yaml

flux create helmrelease universal-crossplane \
    --interval 1h \
    --release-name universal-crossplane \
    --target-namespace upbound-system \
    --create-target-namespace \
    --source HelmRepository/upbound \
    --chart universal-crossplane \
    --chart-version 1.3.0-up.0 \
    --crds CreateReplace \
    --export \
    | tee infra/universal-crossplane-release.yaml

gh repo view \
    vfarcic/crossplane-flux-infra \
    --web

flux create source git infra \
    --url https://github.com/vfarcic/crossplane-flux-infra \
    --branch main \
    --interval 30s \
    --export \
    | tee infra/infra-source.yaml

flux create kustomization infra \
    --source infra \
    --path kustomize \
    --prune true \
    --validation client \
    --interval 1m \
    --export \
    | tee infra/infra-kustomization.yaml

git add .

git commit -m "Infra"

git push

echo "[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
" >aws-creds.conf

echo "/aws-creds.conf" | tee .gitignore

kubectl --namespace upbound-system \
    create secret generic aws-creds \
    --from-file creds=./aws-creds.conf \
    --output json \
    --dry-run=client \
    | kubeseal --format yaml \
    | tee infra/aws-creds.yaml

echo "apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: upbound-system
      name: aws-creds
      key: creds" \
    | tee infra/aws-provider-config.yaml

git add .

git commit -m "AWS"

git push

flux get kustomizations

flux get helmreleases

###########################
# Managing Infrastructure #
###########################

echo "apiVersion: demo.upbound.io/v1alpha1
kind: ClusterClaim
metadata:
  name: a-team
  namespace: a-team
spec:
  id: a-team
  compositionSelector:
    matchLabels:
      provider: aws
      cluster: eks
  parameters:
    nodeSize: small" \
    | tee infra/a-team-cluster.yaml

git add .

git commit -m "My cluster"

git push

kubectl get managed

######################################
# Drift detection and reconciliation #
######################################

# Destroy the node group from the console

#############################
# Destroying infrastructure #
#############################

rm infra/a-team-cluster.yaml

git add .

git commit -m "Removed my cluster"

git push

kubectl get managed

#########################
# Destroying everything #
#########################

gh repo view --web

# Delete the repo

cd ..

rm -rf crossplane-flux

#k3d cluster delete upbound
