# License notice

Three different licenses meet in a running deployment. Keep them apart.

## 1. This repository (MIT)

The Terraform, Compose overrides, sync sidecar, scripts and docs in this repository are
MIT licensed (see `LICENSE`). This repository contains no ArtCraft source code, no
ArtCraft patches and no ArtCraft assets.

## 2. artcraft-personal-server (MIT template, ArtCraft-licensed patches)

`scripts/bootstrap.sh` clones
[junwonkim07/artcraft-personal-server](https://github.com/junwonkim07/artcraft-personal-server)
at the commit pinned in `UPSTREAM.lock`. Its template files are MIT. Its `patches/`
directory is derived from ArtCraft and is offered under the ArtCraft License. It is fetched
onto your server at install time and is not redistributed here.

## 3. ArtCraft (ArtCraft License, not open source)

The Docker build downloads `storytold/artcraft-services` and compiles it on your server.
That code and every image built from it are governed by the ArtCraft License, a
"fair source" license. In summary (the original text governs, this is not legal advice):

- private, personal use is allowed
- no commercial sale, no competing product
- do not remove ArtCraft community or donation links or paid model services
- no use of the ArtCraft name or logo to promote a business without permission

Do not push the images you build to a public registry and do not run this as a service
for other people.

## Affiliation

This is an unofficial community project. It is not affiliated with, endorsed by or
supported by ArtCraft, Storyteller, or the artcraft-personal-server author. "ArtCraft" is
used only to describe what this repository deploys.

## Other components

MinIO and mc are built from source by the upstream template under AGPL-3.0. Caddy
(Apache-2.0) and the AWS CLI image (Apache-2.0) are pulled from Docker Hub unmodified.
