geonmo.dcache
=========

A brief description of the role goes here.

Requirements
------------

Any pre-requisites that may not be covered by Ansible itself or the role should be mentioned here. For instance, if the role uses the EC2 module, it may be a good idea to mention in this section that the boto package is required.

Role Variables
--------------

Use the unified structure below instead of legacy variables.

- dcache_accounts: unified source for both files. If provided, both
  `/etc/grid-security/storage-authzdb` and `/etc/grid-security/grid-vorolemap`
  render from this structure.
  - Fields:
    - username, uid, gid, permission
    - entries: list of {root, path[, permission]}
    - voms_fqans: list of FQAN strings (e.g., /cms/Role=NULL/Capability=NULL)
  - Example:
    - username: cmsusers
      uid: 11704
      gid: 1399
      permission: read-write
      entries:
        - { root: "/", path: "/pnfs/sdfarm.kr/data/cms/" }
      voms_fqans:
        - "/cms/Role=NULL/Capability=NULL"

Dependencies
------------

A list of other roles hosted on Galaxy should go here, plus any details in regards to parameters that may need to be set for other roles, or variables that are used from other roles.

Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - hosts: servers
      roles:
         - { role: username.rolename, x: 42 }

License
-------

BSD

Author Information
------------------

An optional section for the role authors to include contact information, or a website (HTML is not allowed).
