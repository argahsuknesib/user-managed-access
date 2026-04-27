import * as readline from 'readline';
import { seedingPolicies, seedingPolicies2, seedingPolicies3 } from './util/policyExamples';

async function seedForOneClient(id: string) {
    await fetch("http://localhost:4000/uma/policies", { method: 'POST', headers: { 'Authorization': `WebID ${encodeURIComponent(id)}`, 'Content-Type': 'text/turtle' }, body: Buffer.from(seedingPolicies3(id), 'utf-8') });
}

async function deleteForOneClient(id: string) {
    const policyIds = [
        'http://example.org/usagePolicy1-read',
        'http://example.org/usagePolicy1-write',
        'http://example.org/usagePolicy1-append',
        'http://example.org/usagePolicy1a-control-1',
        'http://example.org/usagePolicy1a-control-2',
        'http://example.org/usagePolicy3-create',
        'http://example.org/usagePolicy3b-create',
        'http://example.org/usagePolicy3b-read',
        'http://example.org/usagePolicy3b-write',
        'http://example.org/usagePolicy3b-control',
        'urn:uuid:policy-read',
        'urn:uuid:policy-append',
        'urn:uuid:policy-write',
    ];

    for (const policyId of policyIds) {
        await fetch(`http://localhost:4000/uma/policies/${encodeURIComponent(policyId)}`, {
            method: 'DELETE',
            headers: { 'Authorization': `WebID ${encodeURIComponent(id)}` }
        });
    }
}


async function main() {
    // If an argument is provided, use it as the webID, otherwise use alice's default
    const webId = process.argv[2] || 'http://localhost:3000/alice/profile/card#me';
    const mode = process.argv[3] || 'seed';
    
    if (mode === 'seed') {
        console.log(`Automatically seeding for ${webId}...`);
        await seedForOneClient(webId);
        console.log('Seeding completed');
    } else if (mode === 'delete') {
        console.log(`Automatically deleting for ${webId}...`);
        await deleteForOneClient(webId);
        console.log('Deleting completed');
    } else {
        console.error('Invalid mode. Use "seed" or "delete".');
        process.exit(1);
    }
}

main();
