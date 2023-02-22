
#!/bin/bash

#-------------------------------
# read installation parameters
PROPS_FILE="./rpa.properties"

CHECK_PARAMS=false
while getopts p:c flag
do
    case "${flag}" in
        p) PROPS_FILE=${OPTARG};;
    esac
done

if [[ -z ${PROPS_FILE}"" ]];
then
    # load default props file
    PROPS_FILE="./rpa.properties"
    echo "Sourcing default properties file "
    source ${PROPS_FILE}
else
    if [[ -f ${PROPS_FILE} ]];
    then
        echo "Sourcing properties file "${PROPS_FILE}
        source ${PROPS_FILE}
    else
        echo "ERROR: Properties file "${PROPS_FILE}" not found !!!"
        exit
    fi
fi


ADMIN_NAME=$(oc get secret platform-auth-idp-credentials -n ${RPA_CS_NS} -o jsonpath='{.data.admin_username}' | base64 -d)
ADMIN_PASSWORD=$(oc get secret platform-auth-idp-credentials -n ${RPA_CS_NS} -o jsonpath='{.data.admin_password}' | base64 -d)

echo "Login to pak console with user '${ADMIN_NAME}' to add access grants to users in LDAP"
echo "CP Console: https://"$(oc get routes -n ${RPA_CS_NS} cp-console | grep -v NAME | awk '{print $2}')
echo "Admin: "${ADMIN_NAME}
echo "Password: "${ADMIN_PASSWORD}

echo "RPA API & Console URLs"
oc get cm -n ${RPA_NS} ${RPA_NS}-zen-rpa-routes -o yaml | egrep ".*API:|.*UI:"

echo ""
echo "Login to pak dasboard with LDAP user ${RPA_TENANT_OWNER_NAME} to administer the default '${RPA_TENANT_NAME}' tenant"
echo "CP Dashboard: https://"$(oc get routes -n ${RPA_NS} cpd | grep -v NAME | awk '{print $2}')
