#!/usr/bin/env -S yarn exec tsx

const BASE = 'http://localhost:3000';
const ALICE = `${BASE}/alice/`;
const ACC_NAMES = [ 'acc-x', 'acc-y', 'acc-z' ];
const ACC_CONTAINERS = ACC_NAMES.map((part) => `${ALICE}${part}/`);

async function ensureContainer(url: string): Promise<void> {
  const body = `
@prefix ldp: <http://www.w3.org/ns/ldp#> .
<> a ldp:Container, ldp:BasicContainer .
`.trim();

  const response = await fetch(url, {
    method: 'PUT',
    headers: {
      'content-type': 'text/turtle',
    },
    body,
  });

  if (!response.ok && response.status !== 409) {
    throw new Error(`Failed to create/update container ${url}: ${response.status} ${await response.text()}`);
  }
}

async function configureDerivedMetadata(): Promise<void> {
  const update = `
PREFIX derived: <urn:npm:solid:derived-resources:>
INSERT DATA {
  <${ALICE}> derived:derivedResource
    [ derived:template "derived/acc-x/"; derived:selector <${ALICE}acc-x/*>; derived:filter "latest" ],
    [ derived:template "derived/acc-y/"; derived:selector <${ALICE}acc-y/*>; derived:filter "latest" ],
    [ derived:template "derived/acc-z/"; derived:selector <${ALICE}acc-z/*>; derived:filter "latest" ] .
}
`.trim();

  const response = await fetch(`${ALICE}.meta`, {
    method: 'PATCH',
    headers: {
      'content-type': 'application/sparql-update',
    },
    body: update,
  });

  if (!response.ok) {
    throw new Error(`Failed to update ${ALICE}.meta: ${response.status} ${await response.text()}`);
  }
}

async function main(): Promise<void> {
  for (const container of ACC_CONTAINERS) {
    await ensureContainer(container);
  }
  await configureDerivedMetadata();

  console.log('Configured Alice stream containers and derived metadata:');
  for (const container of ACC_CONTAINERS) {
    console.log(`- source:  ${container}`);
    console.log(`  derived: ${ALICE}derived/${container.split('/').slice(-2, -1)[0]}/`);
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
