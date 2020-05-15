#!/bin/bash

#set -x

if [ "$#" -eq 2 ]; then
   echo "setting namespace to $2"
   NAMESPACE="--namespace=$2"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

## apply the new  configs from the out dir
## but don't update the genesis file / config.
for f in out/*
do
	if [[ "$f" == *"genesis"* ]]; then
	   echo "skip reapplying genesis config"
  else
	   kubectl apply -f $f
	fi
done
echo
kubectl get pods

printf "${GREEN} Enter pod name to run update on (once pods are running again): ${NC} \n "
read POD_NAME

printf "${GREEN} Redeploy all nodes [Y/N]? \n"
printf "${GREEN} 'Y' to redeploy all deployments (takes longer, but all nodes will be peered)\n"
printf "${GREEN} 'N' to only restart the updated node [Y/N]: ${NC} \n"
read FULL_REDEPLOY

if [ "$FULL_REDEPLOY" = "Y" ] || [ "$FULL_REDEPLOY" = "y" ]; then
  #helpers/restart_deployments.sh
  printf "Redeploying all running pods \n"
  helpers/redeploy.sh
  echo "  Waiting for pods to restart."
  # this might take a while, so for now have the user check when all the pods
  # are back up and prompt the script to continue.
  kubectl get pods
  printf "${GREEN} When all deployments are back up, hit any key: ${NC} \n"
  printf "${GREEN} in another window run 'kubectl get -w pods' or 'watch kubectl get pods'"
  read BACK_UP
else
  #helpers/restart_deployments.sh $POD_NAME
  printf "Only redeploying $POD_NAME \n"
  helpers/redeploy.sh $POD_NAME
  echo "  Waiting for pod to restart."
fi

POD=""
while [ -z $POD ]; do
    ## wait for the cluster to come back up.
    POD=$(kubectl get pods $NAMESPACE | grep Running | grep $POD_NAME |  awk '{print $1}')
    sleep 5
    echo " waiting for 5..."
done

echo
printf " ${GREEN} waiting for quorum on Pod [$POD] to startup:${NC} \n"

RES=1;
while [ ${RES} -ne 0 ]; do
  kubectl $NAMESPACE exec -it $POD -c quorum -- /geth-helpers/geth-exec.sh "eth.blockNumber"
  RES=$?
  echo "RES IS $RES"
  sleep 2
done

printf " ${GREEN} Quorum is back up. Running update on POD [$POD] ${NC} \n"

CONTINUE=false;
while ! ${CONTINUE}; do
  echo " checking if pod is back up.."
  #kubectl exec $POD -c quorum -- cat /etc/quorum/qdata/dd/^
  kubectl exec $POD -c quorum -- /etc/quorum/qdata/contracts/raft_add_all_permissioned.sh
  RES=$?
  echo "CONTINUE is $CONTINUE"
  echo "RES is $RES"
  if [ $RES -eq 0 ]; then
    CONTINUE=true
  else
    sleep 5;
  fi
done

RES=1
while [ ${RES} -ne 0 ]; do
  echo "trying to add existing .."
  helpers/raft_add_existing_update.sh $POD
  RES=$?
  echo "RES IS $RES"
done
echo "added existing $FAILED"


echo
printf " ${GREEN} Enter path to update deployment yaml \n"
printf " or <enter> to run all updates in the default \n"
printf " out/deployments/updates/ directory: ${NC} \n"
read PATH_TO_DEPLOYMENT_YAML

if [ -z $PATH_TO_DEPLOYMENT_YAML ]; then
  kubectl apply -f out/deployments/updates/
else
  kubectl apply -f $PATH_TO_DEPLOYMENT_YAML
fi

