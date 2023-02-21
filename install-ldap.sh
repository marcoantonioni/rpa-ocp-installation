#!/bin/bash

#-------------------------------
# read installation parameters
source ./rpa.properties

#-------------------------------
namespaceExist () {
    if [ $(oc get ns $1 | grep $1 | wc -l) -lt 1 ];
    then
        return 0
    fi
    return 1
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
checkParams() {

if [ -f "./ldap_user.ldif" ]; then
  echo "LDIF file is here"
else
  echo "ERROR: file './ldap_user.ldif' must be here"
  exit
fi

if [ -z "${TNS}" ]; then
    echo "ERROR: TNS, namespace not set"
    exit
fi

if [ -z "${ENTITLEMENT_KEY}" ]; then
    echo "ERROR: ENTITLEMENT_KEY, key not set"
    exit
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
createSecrets() {
  oc create secret generic -n ${TNS} icp4adeploy-openldap-secret --from-literal=LDAP_ADMIN_PASSWORD=passw0rd --from-literal=LDAP_CONFIG_PASSWORD=passw0rd
  oc create secret generic -n ${TNS} icp4adeploy-openldap-customldif --from-file=ldap_user.ldif=./ldap_user.ldif

}

#-------------------------------
createServiceAccountAndCfgMap() {

cat << EOF | oc create -n ${TNS} -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ibm-cp4ba-anyuid
imagePullSecrets:
- name: 'ibm-entitlement-key'
EOF

oc adm policy add-scc-to-user anyuid -z ibm-cp4ba-anyuid -n ${TNS}

cat << EOF | oc create -n ${TNS} -f -
kind: ConfigMap
apiVersion: v1
metadata:
  name: icp4adeploy-openldap-env
data:
  LDAP_BACKEND: mdb
  LDAP_DOMAIN: example.org
  LDAP_ORGANISATION: Example Inc.
  LDAP_REMOVE_CONFIG_AFTER_SETUP: 'true'
  LDAP_TLS: 'false'
  LDAP_TLS_ENFORCE: 'false'
EOF

}

#-------------------------------
createDeployment() {
cat << EOF | oc create -n ${TNS} -f -
kind: Deployment
apiVersion: apps/v1
metadata:
  name: icp4adeploy-openldap-deploy
  labels:
    app: icp4adeploy-openldap-deploy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: icp4adeploy-openldap-deploy
  template:
    metadata:
      labels:
        app: icp4adeploy-openldap-deploy
    spec:
      restartPolicy: Always
      initContainers:
        - name: openldap-init-ldif
          image: 'cp.icr.io/cp/cp4a/demo/openldap:1.5.0.2'
          command:
            - sh
            - '-c'
            - cp /customldif/* /ldifworkingdir
          resources:
            limits:
              cpu: 100m
              memory: 128Mi
            requests:
              cpu: 100m
              memory: 128Mi
          volumeMounts:
            - name: customldif
              mountPath: /customldif/ldap_user.ldif
              subPath: ldap_user.ldif
            - name: ldifworkingdir
              mountPath: /ldifworkingdir
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: IfNotPresent
        - resources:
            limits:
              cpu: 100m
              memory: 128Mi
            requests:
              cpu: 100m
              memory: 128Mi
          terminationMessagePath: /dev/termination-log
          name: folder-prepare-container
          command:
            - /bin/bash
            - '-ecx'
            - >
              rm -rf /etc-folder/* && cp -rp /etc/* /etc-folder || true && rm
              -rf /var-lib-folder/* && cp -rp /var/lib/* /var-lib-folder || true
              && (rm -rf /usr-folder/* && cp -rp /usr/sbin/* /usr-folder && rm
              -rf /var-cache-folder/* && cp -rp /var/cache/debconf/*
              /var-cache-folder || true) && rm -rf /container-run-folder/* && cp
              -rp /container/* /container-run-folder || true
          securityContext:
            capabilities:
              drop:
                - ALL
            privileged: false
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - name: usr-folder-pvc
              mountPath: usr-folder
            - name: var-cache-folder-pvc
              mountPath: var-cache-folder
            - name: container-run-folder-pvc
              mountPath: container-run-folder
            - name: etc-ldap-folder-pvc
              mountPath: etc-folder
            - name: var-lib-folder-pvc
              mountPath: var-lib-folder
          terminationMessagePolicy: File
          image: 'cp.icr.io/cp/cp4a/demo/openldap:1.5.0.2'
      serviceAccountName: ibm-cp4ba-anyuid
      terminationGracePeriodSeconds: 30
      securityContext: {}
      containers:
        - resources:
            limits:
              cpu: 500m
              memory: 512Mi
            requests:
              cpu: 100m
              memory: 256Mi
          readinessProbe:
            tcpSocket:
              port: ldap-port
            initialDelaySeconds: 20
            timeoutSeconds: 1
            periodSeconds: 10
            successThreshold: 1
            failureThreshold: 10
          terminationMessagePath: /dev/termination-log
          name: icp4adeploy-openldap-deploy
          livenessProbe:
            tcpSocket:
              port: ldap-port
            initialDelaySeconds: 20
            timeoutSeconds: 1
            periodSeconds: 10
            successThreshold: 1
            failureThreshold: 10
          ports:
            - name: ldap-port
              containerPort: 389
              protocol: TCP
            - name: ssl-ldap-port
              containerPort: 636
              protocol: TCP
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - name: data
              mountPath: /var/lib/ldap
              subPath: data
            - name: data
              mountPath: /etc/ldap/slapd.d
              subPath: config-data
            - name: ldifworkingdir
              mountPath: /container/service/slapd/assets/config/bootstrap/ldif/custom
            - name: etc-ldap-folder-pvc
              mountPath: /etc
            - name: temp-pvc
              mountPath: /tmp
            - name: usr-folder-pvc
              mountPath: /usr/sbin
            - name: var-backup-folder-pvc
              mountPath: /var/backups/slapd-2.4.57+dfsg-3~bpo10+1
            - name: var-lib-folder-pvc
              mountPath: /var/lib
            - name: var-cache-folder-pvc
              mountPath: /var/cache/debconf
            - name: container-run-folder-pvc
              mountPath: /container
          terminationMessagePolicy: File
          envFrom:
            - configMapRef:
                name: icp4adeploy-openldap-env
            - secretRef:
                name: icp4adeploy-openldap-secret
          image: 'cp.icr.io/cp/cp4a/demo/openldap:1.5.0.2'
          args:
            - '--copy-service'
      serviceAccount: ibm-cp4ba-anyuid
      volumes:
        - name: customldif
          secret:
            secretName: icp4adeploy-openldap-customldif
            defaultMode: 420
        - name: ldifworkingdir
          emptyDir: {}
        - name: certs
          emptyDir:
            medium: Memory
        - name: data
          emptyDir: {}
        - name: etc-ldap-folder-pvc
          emptyDir: {}
        - name: temp-pvc
          emptyDir: {}
        - name: usr-folder-pvc
          emptyDir: {}
        - name: var-backup-folder-pvc
          emptyDir: {}
        - name: var-cache-folder-pvc
          emptyDir: {}
        - name: var-lib-folder-pvc
          emptyDir: {}
        - name: container-run-folder-pvc
          emptyDir: {}
EOF

oc expose deployment -n ${TNS} icp4adeploy-openldap-deploy

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

#===============================

checkParams

createNamespace

createEntitlementSecrets

createSecrets

createServiceAccountAndCfgMap

createDeployment

waitForDeploymentReady ${TNS} icp4adeploy-openldap-deploy ${WAIT_SECS}

echo "LDAP installed, wait for pod readiness then use ./showAccessInfo.sh tho show access infos"