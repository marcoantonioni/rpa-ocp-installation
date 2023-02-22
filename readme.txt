Install IBM Robotic Process Automation server environment in OpenShift cluster

Prerequisites:

- storage class (default) with RWO support (in TechZone it is default)
- OCP cluster without previous installation of Automation Foundation operators (RPA not yet compatible with CP4BA core capabilities)
- 3 small size worker nodes
- entitlement key (https://myibm.ibm.com/products-services/containerlibrary)

Installation:

- set environment variable CP4BA_AUTO_ENTITLEMENT_KEY in startup shell scripts (export CP4BA_AUTO_ENTITLEMENT_KEY="...your key...")
- edit rpa.properties file with your needs/preferences
- if there is no IDP for pak install LDAP
-- run command ./install-ldap.sh and wait for completion (options '-c' check variables, '-p' pathname properties file [default './rpa.properties'])
- run command ./install-rpa.sh and wait for completion (options '-c' check variables, '-p' pathname properties file [default './rpa.properties'])


Configuration:

- run command ./showAccessInfo.sh to get access info (options '-p' pathname properties file [default './rpa.properties'])
- access pak console (https://cp-console.itzroks...) to add IDP (openldap) [identity and access -> identity providers - new connection]
   
  example of configuration parameters:

   # set the following values (change the LDAP server URL if necessary, it depends on the installation namespace)
  Name: openldap
  Type: custom
  Base dn: dc=example,dc=org
  Bind dn: cn=admin,dc=example,dc=org
  Bind DN password: passw0rd
  URL: ldap://icp4adeploy-openldap-deploy.rpa.svc.cluster.local:389
  groupFilter:      (&(cn=%v)(objectclass=groupOfNames))
  groupIdMap:       *:cn
  groupMemberIdMap: groupOfNames:member
  userFilter:       (&(uid=%v)(objectclass=person))
  userIdMap:        *:uid

- if not already configured IDP and added users to the pak domain, access to the pak (sso Zen) access console 'cp-console' configure IDP and users access (see pdf)
- log in with 'admin' user to cpd rpa console (https://cpd-rpa.itzroks-...) for "access control" configuration, use Add Users (enter at least the tenant owner), add necessary roles
- log in with user owner of the tenant to cpd rpa (https://cpd-rpa.itzroks-...), log in sso to the tenant for user access administration (import from ldap)
