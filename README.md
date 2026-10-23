geonmo.dcache
=============

Ansible role that installs and configures [dCache](https://www.dcache.org/) on
Enterprise Linux. A single role covers three node layouts:

| `dcache_layout_type` | Node role | What it runs |
|---|---|---|
| `standalone` | All-in-one node | ZooKeeper, core services (admin, poolmanager, pnfsmanager, gPlazma, pinmanager, billing, httpd, frontend), NFS 4.1, XRootD and WebDAV doors, plus the pools in `dcache_volumes`. PostgreSQL is installed locally. |
| `frontend` | Head node without pools | ZooKeeper, info/topo, SRR, core services incl. spacemanager, NFS 4.1, gPlazma, billing, GridFTP, WebDAV and XRootD doors, optional SRM. PostgreSQL is installed locally. |
| `backend` | Pool node | Only the pools in `dcache_volumes`, connected to the ZooKeeper on `dcache_headnode`. No PostgreSQL. |

Requirements
------------

- EL 8/9 (AlmaLinux, Rocky, CentOS Stream, RHEL). On EL9 clones the role enables the CRB repository.
- Java 17 (installed by the role as `java-17-openjdk-headless`).
- Internet access to `dcache.org` (dCache RPM) and, on `frontend`/`standalone`, to `download.postgresql.org` (PGDG repository).
- Ansible collections:

  ```sh
  ansible-galaxy collection install community.general community.postgresql
  ```

- A host certificate in `/etc/grid-security/` for doors that use X.509 (GridFTP, WebDAV/HTTPS, XRootD with GSI). The role can deploy it for you, see [Host certificate](#host-certificate).

Role Variables
--------------

All defaults are in [`defaults/main.yml`](defaults/main.yml).

### General

| Variable | Default | Description |
|---|---|---|
| `dcache_layout_type` | `""` | **Required.** One of `standalone`, `frontend`, `backend`. |
| `dcache_version` | `11.2.9` | dCache version to install from `dcache.org`. |
| `dcache_headnode` | `{{ ansible_fqdn }}` | Host running ZooKeeper. Set it to the head node FQDN on `backend` nodes. |
| `psql_version` | `18` | PostgreSQL major version (PGDG) on `frontend`/`standalone`. |
| `dcache_java_heap` | `4096m` | Default JVM heap for all dCache domains. |
| `dcache_volumes` | `[]` | Pools to create on `standalone`/`backend`: list of `{name, path, size}` (`size` is optional). The role creates `path` owned by `dcache`. |

### dcache service account

| Variable | Default | Description |
|---|---|---|
| `dcache_uid` | `~` | UID for the `dcache` account. |
| `dcache_gid` | `~` | GID for the `dcache` group. |

When unset, the dCache RPM creates the account with the next free system UID,
which usually differs from host to host. **Multi-node sites should set both
values** so that pool data ownership is the same on every host.

When set, the role:

1. creates the local `dcache` group and user with these IDs if the account exists neither locally nor in LDAP/SSSD;
2. fails if an existing account has different IDs. It never changes the UID itself, since that would break ownership of files already on disk.

### Authentication and authorization

| Variable | Default | Description |
|---|---|---|
| `dcache_use_voms` | `true` | Enable X.509/VOMS in gPlazma and render `/etc/grid-security/grid-vorolemap`. |
| `dcache_use_oidc` | `true` | Enable OIDC in gPlazma; uses `multimaps` for mapping. |
| `dcache_use_htpasswd` | `false` | Enable htpasswd authentication in gPlazma. |
| `dcache_htpasswd_users` | `[]` | **Required when `dcache_use_htpasswd` is true.** Users written to `/etc/dcache/htpasswd` on `frontend`/`standalone`: list of `{name, password}`. Keep passwords in Ansible Vault. |
| `dcache_accounts` | `[]` | **Required on `frontend`/`standalone`.** Accounts used to render `storage-authzdb` and `grid-vorolemap`. |
| `multimaps` | `[]` | Entries for `/etc/dcache/multi-mapfile` (OIDC). |

`dcache_accounts` entries:

```yaml
dcache_accounts:
  - username: cmsusers
    uid: 11704
    gid: 1399
    permission: read-write          # default for all entries (read-write | read-only)
    entries:                        # at least one
      - { root: "/", path: "/pnfs/example.org/data/cms/" }
      - { root: "/", path: "/pnfs/example.org/data/cms/store/", permission: read-only }
    voms_fqans:                     # required when dcache_use_voms is true
      - "/cms/Role=NULL/Capability=NULL"
```

`multimaps` entries:

```yaml
multimaps:
  - scheme: op                      # multimap principal type
    principal: MYVO                 # value to match
    uid: 50000
    gid: 50000
    primary: true
    username: vouser
```

### Doors

| Variable | Default | Description |
|---|---|---|
| `dcache_xrootd` | `{readpath: "/", writepath: "/", port: 1094}` | XRootD door settings. |
| `dcache_webdav` | `{cellname: webdav, root: "/", protocol: https, redirect_on_read: false, redirect_on_write: false}` | WebDAV door settings. |
| `dcache_enable_srm` | `false` | Add the SRM door (`frontend` only). |
| `dcache_srm_port` | `8446` | SRM port. |
| `dcache_ftp_limits_clients` | `2000` | GridFTP client limit (`frontend` only). |

### Frontend layout

| Variable | Default | Description |
|---|---|---|
| `dcache_site_unique_id` | — | **Required on `frontend`.** `info-provider.site-unique-id`, e.g. `EXAMPLE-SITE`. |
| `dcache_srr_shares` | — | **Required on `frontend`.** `frontend.srr.shares`, e.g. `default:myvo`. |
| `dcache_srr_storage_descriptor_path` | `""` | If set, `storage-descriptor.output.path`. |
| `dcache_linkgroup_authorization_file` | `/etc/dcache/LinkGroupAuthorization.conf` | Space manager link group authorization file. |

### Standalone layout

| Variable | Default | Description |
|---|---|---|
| `dcache_kerberos_realm` | `""` | If set, `dcache.authn.kerberos.realm`. |
| `dcache_xrootd_java_heap` | `16384m` | JVM heap of the XRootD door domain. |
| `dcache_webdav_java_heap` | `16384m` | JVM heap of the WebDAV door domain. |
| `dcache_star_gid_mapping` | `{}` | If set, `star.gid-mapping` for tape integration, e.g. `{1399: "/cms", 45000: "/ops"}`. |

### Pool flow marking (SciTags fireflies)

| Variable | Default | Description |
|---|---|---|
| `dcache_pool_enable_firefly` | `false` | Enable firefly packets on pools. dCache 11.2.4 or later is recommended. |
| `dcache_pool_firefly_destination` | `collector.scitags.org:10514` | Additional collector that receives a copy of each firefly (the global SciTags collector operated by ESnet). Set to `""` to send fireflies only to the transfer peer (UDP 10514). |
| `dcache_pool_firefly_excludes` | `[]` | Networks that are not marked, e.g. `["10.0.0.0/8", "192.168.0.0/16"]`. |

See [scitags.org](https://www.scitags.org) for details.

### Host certificate

| Variable | Default | Description |
|---|---|---|
| `dcache_manage_hostcert` / `dcache_manage_hostkey` | `false` | Deploy `/etc/grid-security/hostcert.pem` / `hostkey.pem`. |
| `dcache_hostcert_pem` / `dcache_hostkey_pem` | `~` | Inline PEM content (e.g. from Ansible Vault). Takes precedence over the file source. |
| `dcache_hostcert_src` / `dcache_hostkey_src` | `~` | Source file on the controller. Required when managing the file without inline PEM. |
| `dcache_cert_owner`, `dcache_cert_group`, `dcache_key_owner`, `dcache_key_group` | `dcache` | Ownership of the deployed files. |

Dependencies
------------

None.

Example Playbook
----------------

A head node and two pool nodes:

```yaml
# group_vars/dcache.yml
dcache_uid: 2000
dcache_gid: 2000
dcache_headnode: dcache-head.example.org
dcache_accounts:
  - username: myvo
    uid: 30000
    gid: 30000
    entries:
      - { root: "/", path: "/pnfs/example.org/data/myvo/" }
    voms_fqans:
      - "/myvo/Role=NULL/Capability=NULL"
```

```yaml
# site.yml
- hosts: dcache_head
  become: true
  roles:
    - role: geonmo.dcache
      vars:
        dcache_layout_type: frontend
        dcache_site_unique_id: EXAMPLE-SITE
        dcache_srr_shares: "default:myvo"
        dcache_manage_hostcert: true
        dcache_manage_hostkey: true

- hosts: dcache_pools
  become: true
  roles:
    - role: geonmo.dcache
      vars:
        dcache_layout_type: backend
        dcache_volumes:
          - { name: "{{ inventory_hostname_short }}-pool01", path: /data/dcache/01 }
          - { name: "{{ inventory_hostname_short }}-pool02", path: /data/dcache/02, size: 100T }
        dcache_pool_enable_firefly: true
        dcache_pool_firefly_excludes: ["10.0.0.0/8"]
```

Testing
-------

The [`tests/`](tests) directory has one playbook per layout. They share the
values in [`tests/vars/common.yml`](tests/vars/common.yml) and use only
example names and private address ranges.

| Playbook | Layout | Covers |
|---|---|---|
| `test.yml` | `standalone` | Fixed UID/GID, accounts with per-entry permissions, OIDC multimap, XRootD/WebDAV settings, Kerberos realm, STAR GID mapping, two pools with fireflies |
| `test-frontend.yml` | `frontend` | Required SRR/info-provider values, storage descriptor, GridFTP limit, SRM enabled |
| `test-backend.yml` | `backend` | Pools attached to a remote head node, fireflies |

Run each on a fresh EL host (as root):

```sh
ansible-playbook -i tests/inventory tests/test.yml
```

Known limitations
-----------------

- dCache is restarted (`dcache restart`) on every run.
- The dCache RPM is not upgraded if any version is already installed.

License
-------

BSD-3-Clause

Author Information
------------------

Geonmo Ryu, Global Science experimental Data hub Center (GSDC), Korea Institute of Science and Technology Information (KISTI).
