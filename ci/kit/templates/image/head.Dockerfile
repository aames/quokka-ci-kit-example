# The job image's toolchain layer on the kit's base.
#
# ci/kit/bin/container builds this, never a person, from a context of exactly
# the manifest's image-path list at the commit under test, FROM the kit's base
# image by the build argument CIKIT_BASE, and labels it with its key itself.
# It is built on each machine for that machine's own architecture and never
# pulled.
#
# The pins live where the tools read them (the manifest's pin-source lines).
# This file names the same versions with each release tarball's sha256 for
# both architectures, and the build stops if the two disagree, so a pin bump
# is one reviewed edit of the pin file and this file together.

ARG CIKIT_BASE
FROM ${CIKIT_BASE}
