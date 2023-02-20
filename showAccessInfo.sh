
#!/bin/bash

#-------------------------------
# read installation parameters
source ./rpa.properties


ADMIN_NAME=$(oc get secret platform-auth-idp-credentials -n ${CS_NS} -o jsonpath='{.data.admin_username}' | base64 -d)
ADMIN_PASSWORD=$(oc get secret platform-auth-idp-credentials -n ${CS_NS} -o jsonpath='{.data.admin_password}' | base64 -d)

echo "Login to pak console with user '${ADMIN_NAME}' to add access grants to users in LDAP"
echo "CP Console: https://"$(oc get routes -n ${CS_NS} cp-console | grep -v NAME | awk '{print $2}')
echo "Admin: "${ADMIN_NAME}
echo "Password: "${ADMIN_PASSWORD}

echo "RPA API & Console URLs"
oc get cm -n ${TNS} rpa-zen-rpa-routes -o yaml | egrep ".*API:|.*UI:"

echo ""
echo "Login to pak dasboard with LDAP user ${RPA_TENANT_OWNER_NAME} to administer the default '${RPA_TENANT_NAME}' tenant"
echo "CP Dashboard: https://"$(oc get routes -n ${TNS} cpd | grep -v NAME | awk '{print $2}')
