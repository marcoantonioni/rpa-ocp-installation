#!/bin/bash

#-------------------------------
# read installation parameters
source ./rpa.properties

#-------------------------------
storageClassExist () {
    if [ $(oc get sc ${SC_NAME} | grep ${SC_NAME} | wc -l) -lt 1 ];
    then
        return 0
    fi
    return 1
}

#-------------------------------
namespaceExist () {
    if [ $(oc get ns $1 | grep $1 | wc -l) -lt 1 ];
    then
        return 0
    fi
    return 1
}

#-------------------------------
resourceExist () {
    if [ $(oc get $2 -n $1 $3 | grep $3 | wc -l) -lt 1 ];
    then
        return 0
    fi
    return 1
}

#-------------------------------
waitForResourceCreated () {
#    echo "namespace name: $1"
#    echo "resource type: $2"
#    echo "resource name: $3"
#    echo "time to wait: $4"

    while [ true ]
    do
        resourceExist $1 $2 $3 $4
        if [ $? -eq 0 ]; then
            echo "Wait for resource '$3' in namespace '$1' created, sleep $4 seconds"
            sleep $4
        else
            break
        fi
    done
}

#-------------------------------
waitForResourceReady () {
#    echo "namespace name: $1"
#    echo "resource type: $2"
#    echo "resource name: $3"
#    echo "time to wait: $4"

    while [ true ]
    do
        _READY=$(oc get $2 -n $1 $3 -o jsonpath="{.status.connectionState.lastObservedState}")
        if [ "${_READY}" = "READY" ]; then
            echo "Resource '$3' in namespace '$1' is READY"
            break
        else
            echo "Wait for resource '$3' in namespace '$1' to be READY, sleep $4 seconds"
            sleep $4
        fi
    done
}

#-------------------------------
waitForDeploymentReady () {
#    echo "namespace name: $1"
#    echo "resource name: $2"
#    echo "time to wait: $3"

    while [ true ]
    do
        REPLICAS=$(oc get deployment -n $1 $2 -o jsonpath="{.status.replicas}")
        READY_REPLICAS=$(oc get deployment -n $1 $2 -o jsonpath="{.status.readyReplicas}")
        if [ "${REPLICAS}" = "${READY_REPLICAS}" ]; then
            echo "Resource '$2' in namespace '$1' is READY"
            break
        else
            echo "Wait for resource '$2' in namespace '$1' to be READY, sleep $3 seconds"
            sleep $3
        fi
    done
}

#-------------------------------
waitForPodRunning () {
#    echo "namespace name: $1"
#    echo "resource name: $2"
#    echo "time to wait: $3"

    while [ true ]
    do
        PHASE=$(oc get pod -n $1 $2 -o jsonpath='{.status.phase}')
        if [ "${PHASE}" = "Running" ]; then
            echo "Pod '$2' in namespace '$1' is Running"
            break
        else
            echo "Wait for pod '$2' in namespace '$1' to be Running, sleep $3 seconds"
            sleep $3
        fi
    done
}

#-------------------------------
checkParams() {

if [ -z "${TNS}" ]; then
    echo "ERROR: TNS, namespace not set"
    exit
fi

if [ -z "${RPA_DB_NAME}" ]; then
    echo "ERROR: RPA_DB_NAME, db name not set"
    exit
fi

if [ -z "${RPA_DB_PORT}" ]; then
    echo "ERROR: RPA_DB_PORT, db port not set"
    exit
fi

if [ -z "${RPA_DB_USER}" ]; then
    echo "ERROR: RPA_DB_USER, db user not set"
    exit
fi

if [ -z "${RPA_DB_PASS}" ]; then
    echo "ERROR: RPA_DB_PASS, db password not set"
    exit
fi

if [ -z "${ENTITLEMENT_KEY}" ]; then
    echo "ERROR: ENTITLEMENT_KEY, key not set"
    exit
fi

storageClassExist
if [ $? -eq 0 ]; then
    echo "ERROR: Storage class not found"
    exit
fi

}

#-------------------------------
patch_nfs4() {

if [ "${PATCH_NFS_DOMAIN}" = "true" ]; then
   oc get no -l node-role.kubernetes.io/worker --no-headers -o name | xargs -I {} \
      -- oc debug -n default {} \
      -- chroot /host sh -c 'grep "^Domain = slnfsv4.coms" /etc/idmapd.conf || ( sed -i "s/.*Domain =.*/Domain = slnfsv4.com/g" /etc/idmapd.conf; nfsidmap -c; rpc.idmapd )'
fi

}

#-------------------------------
createNamespace() {
   namespaceExist ${TNS}
   if [ $? -eq 0 ]; then
      oc new-project ${TNS}
   fi
}

#-------------------------------
deployDb() {

   resourceExist ${TNS} deployment mssql
   if [ $? -eq 0 ]; then
      oc new-app --name mssql -n ${TNS} -e NAME=mssql SA_PASSWORD=${RPA_DB_PASS} -e ACCEPT_EULA=Y -e MSSQL_PID=Express -e VOLUME_CAPACITY=512Mi mcr.microsoft.com/mssql/rhel/server:2019-latest

      waitForResourceCreated ${TNS} deployment mssql ${WAIT_SECS}

      waitForDeploymentReady ${TNS} mssql ${WAIT_SECS}
   fi

}

#-------------------------------
createSecrets() {

   # db secret
   oc create secret generic rpa-db -n ${TNS} \
   --from-literal=AddressContext="${RPA_DB_CONN_PARAMS_ADDRESS}" \
   --from-literal=AutomationContext="${RPA_DB_CONN_PARAMS_AUTOMATION}" \
   --from-literal=KnowledgeBase="${RPA_DB_CONN_PARAMS_KNOWLEDGE}" \
   --from-literal=WordnetContext="${RPA_DB_CONN_PARAMS_WORDNET}" \
   --from-literal=AuditContext="${RPA_DB_CONN_PARAMS_AUDIT}"

   # smtp secret
   oc create secret generic rpa-smtp -n ${TNS} --from-literal=username=${SMTP_USER} --from-literal=password=${SMTP_PASSWORD}

}

#-------------------------------
deployMsSqlToolsPod() {

cat <<EOF | oc create -f -
kind: Pod
apiVersion: v1
metadata:
  name: mssql-tools
  namespace: ${TNS}
  labels:
    app: mssql-tools
spec:
  containers:
    - name: mssql-tools
      image: 'mcr.microsoft.com/mssql-tools'
      command: [ "/bin/bash", "-c", "sleep infinity" ]
EOF

waitForPodRunning ${TNS} mssql-tools ${WAIT_SECS}

}

#-------------------------------
createRpaDatabases() {
   oc rsh -n ${TNS} mssql-tools /opt/mssql-tools/bin/sqlcmd -S mssql.${TNS}.svc.cluster.local -U sa -P ${RPA_DB_PASS} -Q "create database [automation]; create database [knowledge]; create database [wordnet]; create database [address]; create database [audit];"
}

#-------------------------------
createEntitlementSecrets() {

oc create secret docker-registry -n ${TNS} pull-secret \
    --docker-server=cp.icr.io \
    --docker-username=cp \
    --docker-password="${ENTITLEMENT_KEY}"

oc secrets link -n ${TNS} default pull-secret --for=pull

oc create secret docker-registry -n ${TNS} ibm-entitlement-key \
    --docker-server=cp.icr.io \
    --docker-username=cp \
    --docker-password="${ENTITLEMENT_KEY}"

}

#-------------------------------
createCatalogSource() {
   resourceExist openshift-marketplace CatalogSource ibm-operator-catalog
   if [ $? -eq 0 ]; then

cat <<EOF | oc create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: IBM Operator Catalog
  image: icr.io/cpopen/ibm-operator-catalog:latest
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 45m
EOF

   fi
}

#-------------------------------
createOperatorGroup() {

   resourceExist ${TNS} OperatorGroup ibm-cp4a-operator-catalog-group
   if [ $? -eq 0 ]; then

      resourceExist ${TNS} OperatorGroup rpa-group
      if [ $? -eq 0 ]; then

cat <<EOF | oc create -f - 
apiVersion: operators.coreos.com/v1alpha2 
kind: OperatorGroup 
metadata: 
  name: rpa-group
  namespace: ${TNS}
spec: 
  targetNamespaces: 
  - ${TNS}
EOF

      fi

   fi
}

#-------------------------------
createRpaSubscription() {

   resourceExist ${TNS} Subscription rpa-subscription
   if [ $? -eq 0 ]; then

cat <<EOF | oc create -f - 
apiVersion: operators.coreos.com/v1alpha1 
kind: Subscription 
metadata: 
  name: rpa-subscription
  namespace: ${TNS}
spec: 
  name: ibm-automation-rpa 
  channel: ${RPA_CHANNEL_VER}
  installPlanApproval: Automatic 
  source: ibm-operator-catalog 
  sourceNamespace: openshift-marketplace
EOF

   fi

    while [ true ]
    do

      if [ $(oc get CustomResourceDefinition roboticprocessautomations.rpa.automation.ibm.com | grep -v NAME | wc -l) -lt 1 ];
      then
         sleep ${WAIT_SECS}
      else
         break
      fi

    done

}

#-------------------------------
createRpaDeployment() {

cat <<EOF | oc create -f -
apiVersion: rpa.automation.ibm.com/v1beta1
kind: RoboticProcessAutomation
metadata:
  name: ${RPA_INSTANCE_NAME}
  namespace: ${TNS}
spec:
  license:
    accept: true
  createRoutes: false
  webDriverUpdates:
    enabled: true
  systemQueueProvider:
    highAvailability: false
  ui:
    replicas: 1
  hotStorageCleanup:
    enabled: true
  version: ${RPA_VERSION}
  api:
    externalConnection:
      secretName: rpa-db
    firstTenant:
      owner:
        email: ${RPA_TENANT_OWNER_EMAIL}
        name: ${RPA_TENANT_OWNER_NAME}
      name: ${RPA_TENANT_NAME}
    smtp:
      userSecret:
        secretName: rpa-smtp
      port: 66
      server: 127.0.0.1
    storage: {}
    replicas: 1
  antivirus:
    replicas: 1
  tls: {}
  audit:
    forwardingEnabled: true
  ocr:
    replicas: 1
EOF

}

#-------------------------------
waitRpaReady() {
   READY=
    while [ true ]
    do
        _READY=$(oc get roboticprocessautomations.rpa.automation.ibm.com -n ${TNS} ${RPA_INSTANCE_NAME} | grep -v NAME | awk '{print $2}')
        if [ "${_READY}" = "True" ]; then
            echo "Resource '${RPA_INSTANCE_NAME}' in namespace '${TNS}' is READY"
            break
        else
            echo "Wait for RPA instance '${RPA_INSTANCE_NAME}' in namespace '${TNS}' to be READY, sleep ${WAIT_SECS} seconds"
            sleep ${WAIT_SECS}
        fi
    done
}

#-------------------------------
WORKAROUND_serviceAccounts() {
   
   waitForResourceCreated ${TNS} sa rpa-redis-rpa ${WAIT_SECS}
   waitForResourceCreated ${TNS} sa rpa-mq-rpa-ibm-mq ${WAIT_SECS}

   oc secrets link -n ${TNS} rpa-redis-rpa pull-secret --for=pull
   oc adm policy add-scc-to-user anyuid -z rpa-mq-rpa-ibm-mq -n ${TNS}
   
}


#===========================================
echo "Installing RPA"

checkParams

storageClassExist

patch_nfs4

createNamespace

deployDb

createSecrets

deployMsSqlToolsPod

createRpaDatabases

createEntitlementSecrets

createCatalogSource

createOperatorGroup

createRpaSubscription

createRpaDeployment

WORKAROUND_serviceAccounts

waitRpaReady

echo "RPA installation completed"
echo "Use ./showAccessInfo.sh tho show access infos"