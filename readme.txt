Installazione ambiente RPA in cluster OpenShift

Prerequisiti:

- storage class (default) con supporto RWO (in TechZone è predefinita)
- cluster OCP senza precedente installazione di operatori Automation Foundation (RPA ancora non compatibile con CP4BA core capabilities)
- 3 worker nodes di taglia piccola
- entitlement key (https://myibm.ibm.com/products-services/containerlibrary)

Installazione:

- impostare variabile di ambiente CP4BA_AUTO_ENTITLEMENT_KEY nella shell di avvio scripts (export CP4BA_AUTO_ENTITLEMENT_KEY="...vostra key...")
- modificare file rpa.properties con vostre necessità/preferenze
- se non presente un IDP per pak installare LDAP
-- avviare comando ./install-ldap.sh e attendere completamento (opzioni '-c' verifica variabili, '-p' pathname file di properties [default './rpa.properties'])
- avviare comando ./install-rpa.sh e attendere completamento (opzioni '-c' verifica variabili, '-p' pathname file di properties [default './rpa.properties'])

Configurazione:

- avviare comando ./showAccessInfo.sh per ottenere info di accesso (opzioni '-p' pathname file di properties [default './rpa.properties'])
- eseguire accesso a console pak (https://cp-console.itzroks...) per aggiungere IDP (openldap) [identity and access -> identity providers - new connection]
  esempio di parametri di configurazione:

  # impostare i seguenti valori (modificare se necessario la URL del server LDAP, dipende dal namespace di installazione)
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

- se non già configurato IDP e aggiunti utenti al dominio del pak, accesso al pak (sso Zen) accedere a console 'cp-console' configurare IDP e accesso utenti (vedi pdf)
- eseguire accesso con utenza 'admin' a console cpd rpa (https://cpd-rpa.itzroks-...) per configurazione "access control", usare Add Users (inserire almeno l'owner del tenant), aggiungere ruoli necessari
- eseguire accesso con utenza owner del tenant a cpd rpa (https://cpd-rpa.itzroks-...), eseguire login sso al tenant per amministrazione accesso utenti (import from ldap)

