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
- Ansible collections `community.general` and `community.postgresql` (installed by `requirements.yml`, see below).
- A host certificate in `/etc/grid-security/` for doors that use X.509 (GridFTP, WebDAV/HTTPS, XRootD with GSI). The role can deploy it for you, see [Host certificate](#host-certificate).

Installation
------------

Copy [`requirements.yml`](requirements.yml) into your playbook repository and
run:

```sh
ansible-galaxy install -r requirements.yml
```

It installs this role from GitHub under the name `geonmo.dcache`, plus the
required collections:

```yaml
roles:
  - name: geonmo.dcache
    src: https://github.com/gsdc/ansible-role-dcache.git
    scm: git
    version: main

collections:
  - name: community.general
  - name: community.postgresql
```

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
| `dcache_net_wan_port_min` / `dcache_net_wan_port_max` | `20000` / `25000` | WAN port range used by movers that talk to external clients. Open it in the firewall on pool nodes. The role also puts pool XRootD movers in this range (dCache 11.2 uses the LAN range for them by default); for an internal-only XRootD setup, override `pool.mover.xrootd.port.min/max` in the corresponding cell section of the layout. |
| `dcache_net_lan_port_min` / `dcache_net_lan_port_max` | `30000` / `35000` | LAN port range for internal connections between dCache domains. |
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
| `dcache_use_oidc` | `false` | Enable OIDC/token authentication in gPlazma. |
| `dcache_oidc_providers` | `[]` | **Required when `dcache_use_oidc` is true.** Trusted token issuers: list of `{name, issuer, options}`, rendered as `gplazma.oidc.provider!<name> = <issuer> <options>`. No provider is trusted by default. |
| `dcache_oidc_audience_targets` | `https://wlcg.cern.ch/jwt/v1/any`, `<dcache_headnode>`, `https://<dcache_headnode>` | Accepted token `aud` values (`gplazma.oidc.audience-targets`). Tokens whose `aud` matches none of them are rejected. List the names clients use to reach the doors (the SE endpoint registered in CRIC), including DNS aliases and `scheme://host:port` variants such as `roots://se.example.org:1094` if needed. |
| `dcache_use_htpasswd` | `false` | Enable htpasswd authentication in gPlazma. |
| `dcache_htpasswd_users` | `[]` | **Required when `dcache_use_htpasswd` is true.** Users written to `/etc/dcache/htpasswd` on `frontend`/`standalone`: list of `{name, password}`. Keep passwords in Ansible Vault. |
| `dcache_accounts` | `[]` | **Required on `frontend`/`standalone`.** Accounts used to render `storage-authzdb` and `grid-vorolemap`. |
| `multimaps` | `[]` | Entries for `/etc/dcache/multi-mapfile` (OIDC). |

`dcache_accounts` entries:

```yaml
dcache_accounts:
  - username: cmsprod
    uid: 61001
    gid: 2610
    permission: read-write          # default for all entries (read-write | read-only)
    entries:                        # at least one
      - { root: "/", path: "/pnfs/example.org/data/cms/" }
      - { root: "/", path: "/pnfs/example.org/data/cms/archive/", permission: read-only }
    voms_fqans:                     # required when dcache_use_voms is true
      - "/cms/Role=production/Capability=NULL"
```

`dcache_oidc_providers` and `multimaps` entries (tokens from the CMS issuer are
mapped to the `cmsprod` account):

```yaml
dcache_use_oidc: true
dcache_oidc_providers:
  - name: cms
    issuer: "https://cms-auth.cern.ch/"
    options: "-profile=wlcg -prefix=/pnfs/example.org/data/cms"   # optional
multimaps:
  - scheme: op                      # OIDC provider principal
    principal: cms                  # provider name from dcache_oidc_providers
    uid: 61001
    gid: 2610
    primary: true
    username: cmsprod
```

See the `gplazma.oidc.provider` section of dCache's `gplazma.properties` for
the available options (`-profile`, `-prefix`, `-authz-id`, `-suppress`, ...).

### Doors

| Variable | Default | Description |
|---|---|---|
| `dcache_xrootd` | `{readpath: "/", writepath: "/", port: 1094}` | XRootD door settings. |
| `dcache_xrootd_plugins` | `""` | If set, `xrootd.plugins`. dCache 11.2 default: `gplazma:ztn,gplazma:gsi,gplazma:none,authz:scitokens`. Example for a door that only accepts tokens or X.509: `gplazma:ztn,gplazma:gsi,authz:scitokens`. |
| `dcache_xrootd_tls_mode` | `""` | If set, `xrootd.security.tls.mode` (`OFF`, `OPTIONAL`, `STRICT`; dCache default `OPTIONAL`). `STRICT` refuses clients without TLS. Any mode except `OFF` needs the host certificate on the door node. |
| `dcache_xrootd_root` | `""` | If set, `xrootd.root`. Example: `/pnfs/example.org/data/cms`, so that CMS `/store/...` paths resolve to `/pnfs/example.org/data/cms/store/...`. |
| `dcache_gplazma_gridmap_file` | `""` | If set, `gplazma.gridmap.file` (dCache default `/etc/grid-security/grid-mapfile`). Example: `/etc/grid-security/grid-mapfile-local`. |
| `dcache_webdav` | `{cellname: webdav, root: "/", protocol: https, redirect_on_read: false, redirect_on_write: false}` | WebDAV door settings. |
| `dcache_enable_srm` | `false` | Add the SRM door (`frontend` only). |
| `dcache_srm_port` | `8446` | SRM port. |
| `dcache_ftp_limits_clients` | `2000` | GridFTP client limit (`frontend` only). |

### Frontend layout

| Variable | Default | Description |
|---|---|---|
| `dcache_site_unique_id` | — | **Required on `frontend`.** `info-provider.site-unique-id`, e.g. `EXAMPLE-SITE`. |
| `dcache_srr_shares` | — | **Required on `frontend`.** `frontend.srr.shares`, e.g. `default:cms`. |
| `dcache_srr_storage_descriptor_path` | `""` | If set, `storage-descriptor.output.path`. |
| `dcache_linkgroup_authorization_file` | `/etc/dcache/LinkGroupAuthorization.conf` | Space manager link group authorization file. |
| `dcache_linkgroup_authorizations` | `[{name: default_linkGroup, fqans: ["/*/Role=*"]}]` | Link groups and the FQANs allowed to reserve space in them, rendered into `dcache_linkgroup_authorization_file`. The link groups themselves must still be created in the admin interface. |

### Standalone layout

| Variable | Default | Description |
|---|---|---|
| `dcache_kerberos_realm` | `""` | If set, `dcache.authn.kerberos.realm`. |
| `dcache_xrootd_java_heap` | `16384m` | JVM heap of the XRootD door domain. |
| `dcache_webdav_java_heap` | `16384m` | JVM heap of the WebDAV door domain. |
| `dcache_star_gid_mapping` | `{}` | If set, `star.gid-mapping` for tape integration, e.g. `{2610: "/cms"}`. |

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
  - username: cmsprod
    uid: 61001
    gid: 2610
    entries:
      - { root: "/", path: "/pnfs/example.org/data/cms/" }
    voms_fqans:
      - "/cms/Role=production/Capability=NULL"
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
        dcache_srr_shares: "default:cms"
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
| `test.yml` | `standalone` | Fixed UID/GID, accounts with per-entry permissions, OIDC provider and multimap, XRootD/WebDAV settings, Kerberos realm, STAR GID mapping, two pools with fireflies |
| `test-frontend.yml` | `frontend` | Required SRR/info-provider values, storage descriptor, GridFTP limit, SRM enabled |
| `test-backend.yml` | `backend` | Pools attached to a remote head node, fireflies |

Run each on a fresh EL host (as root):

```sh
ansible-playbook -i tests/inventory tests/test.yml
```

Manual post-installation steps
------------------------------

The role does **not** configure the pool selection unit or space reservations.
After the first deployment, log in to the admin interface on the head node
(`frontend`/`standalone`) and set them up by hand.

**The order matters.** The SRR (storage resource reporting) endpoint only
reports capacity for space that has been reserved, so the storage shows up
with no capacity until all of the following are done, in this order:

> pools → pool group (`pgroup`) → link → link group → link group capacity
> visible in `SpaceManager` → space reserved for each project (VO) quota →
> `WriteToken` tag set on the project directory in Chimera

Space reservation (steps 3-5) is optional: dCache stores data without it, and
if you do not need capacity reporting in SRR you can stop after step 2. It is
still recommended, since SRR is what WLCG uses to account for the storage and
reservations give each project (VO) its own quota.

Steps:

1. Allow admin login: put your SSH public key in
   `/etc/dcache/admin/authorized_keys2` on the head node, then connect:

   ```sh
   ssh -p 22224 admin@dcache-head.example.org
   ```

2. Put the pools in a pool group, attach it to a link and the link to a link
   group in the `PoolManager` cell, then `save` so the setup is written to
   `/var/lib/dcache/config/poolmanager.conf`:

   ```
   \c PoolManager
   psu create pgroup cms-pools
   psu addto pgroup cms-pools <pool-name>
   psu create unit -store cms:cms@osm
   psu create ugroup cms-units
   psu addto ugroup cms-units cms:cms@osm
   psu create link cms-link cms-units world-net
   psu set link cms-link -readpref=10 -writepref=10 -cachepref=10 -p2ppref=-1
   psu addto link cms-link cms-pools
   psu create linkGroup cms-linkgroup
   psu set linkGroup replicaAllowed cms-linkgroup true
   psu set linkGroup onlineAllowed cms-linkgroup true
   psu addto linkGroup cms-linkgroup cms-link
   save
   ```

3. Allow VOs to reserve space in the link group. The role writes
   `/etc/dcache/LinkGroupAuthorization.conf` (`dcache_linkgroup_authorization_file`)
   on the `frontend` node from `dcache_linkgroup_authorizations`; use the same
   link group names as in step 2 and re-run the role:

   ```yaml
   dcache_linkgroup_authorizations:
     - name: cms-linkgroup
       fqans: ["/cms/Role=*"]
     - name: default_linkGroup
       fqans: ["/*/Role=*"]
   ```

4. In the `SpaceManager` cell, check that the link group shows the expected
   free space, then reserve the project quota in it. Once the reservation
   exists, its capacity appears in SRR.

   ```
   \c SpaceManager
   ls link groups
   reserve space -owner=/cms -desc=CMS -lg=cms-linkgroup -al=online -rp=replica 100T
   ls spaces
   ```

   If the link group shows no free space, the pools are not reachable through
   it yet; recheck step 2 (pool group membership, link and link group).

5. Bind the project directory to the reservation: open the Chimera shell and
   set the `WriteToken` directory tag to the space token ID shown by
   `ls spaces` (first column). New files written below the directory then go
   into that reservation. This is the last step.

   ```
   chimera
   mkdir /pnfs/example.org/data/cms          (skip if it already exists)
   writetag /pnfs/example.org/data/cms WriteToken <space-token-id>
   readtag /pnfs/example.org/data/cms WriteToken
   ```

The commands above are examples; see the
[dCache Book](https://www.dcache.org/manuals/) for the pool selection unit and
space manager in detail.

CMS TFC XRootD plugin (optional)
--------------------------------

Some CMS sites run an extra XRootD door that maps CMS logical file names with
the site's TFC (`storage.xml`), using the `cms-tfc` authorization plugin. The
plugin is **not** part of the dCache RPM and this role does not install or
configure it.

Most sites do not need it: if every `/store/...` LFN maps to the same prefix
(e.g. `/pnfs/example.org/data/cms/store/...`), set `dcache_xrootd_root` instead.
The plugin is only useful when the TFC has rules that a single root cannot
express (different prefixes per LFN area, regular expressions, ...).

- Source: [dCache/xrootd4j-cms-plugin](https://github.com/dCache/xrootd4j-cms-plugin)
  (latest tag `xrootd4j-cms-plugin-4.0.4`, last updated 2020-11). There are no
  binary releases on GitHub, so build it yourself:

  ```sh
  git clone https://github.com/dCache/xrootd4j-cms-plugin.git
  cd xrootd4j-cms-plugin
  mvn package
  ```

  The plugin is built against xrootd4j 4.0.4, while dCache 11.2 ships
  xrootd4j 4.6.7. If it does not load, try rebuilding with
  `mvn package -Dversion.xrootd4j=4.6.7` (untested).

- Install: copy the plugin directory produced under `target/` to
  `/usr/local/share/dcache/plugins/` on the door node (one of the directories
  in `dcache.paths.plugins`) and restart the door. If dCache cannot find it,
  the door fails with `Authorization plugin not found: cms-tfc`.

- Configure the door, for example:

  ```
  [xrootd2Domain]
  [xrootd2Domain/xrootd]
  xrootd.net.port=1096
  xrootd.plugins=gplazma:none,authz:cms-tfc
  xrootd.cms.tfc.path=/etc/dcache/storage.xml
  xrootd.cms.tfc.protocol=direct
  ```

  The plugin defaults are `xrootd.cms.tfc.path=file:///etc/xrootd/storage.xml`
  and `xrootd.cms.tfc.protocol=root`. The role rewrites the layout file on
  every run, so keep a door like this in your own copy of the layout template.

Known limitations
-----------------

- dCache is restarted (`dcache restart`) on every run.
- The dCache RPM is not upgraded if any version is already installed.
- Links, link groups and space reservations are not managed by the role; see [Manual post-installation steps](#manual-post-installation-steps).
- Disk-only sites are assumed (e.g. WLCG Tier-2): only `cleaner-disk` is deployed. Sites with tape (HSM) pools need to add `cleaner-hsm` and the HSM settings themselves.

License
-------

BSD-3-Clause

Author Information
------------------

Geonmo Ryu, Global Science experimental Data hub Center (GSDC), Korea Institute of Science and Technology Information (KISTI).
