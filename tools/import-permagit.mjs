import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { gunzipSync } from 'node:zlib';

const repo = process.argv[2] || 'lapee';
const outDir = process.argv[3] || repo;
const requestedRefOrCommit = process.argv[4] || process.env.PERMAGIT_REF || process.env.PERMAGIT_COMMIT || '';
const gateway = process.env.ARWEAVE_GATEWAY || 'https://arweave.net';
const EMPTY_BLOB_SHA = 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391';

async function gql(query) {
  const response = await fetch(`${gateway}/graphql`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  if (!response.ok) throw new Error(`GraphQL failed: ${response.status}`);
  const json = await response.json();
  if (json.errors) throw new Error(JSON.stringify(json.errors));
  return json.data;
}

async function bytes(txId) {
  const response = await fetch(`${gateway}/${txId}`);
  if (!response.ok) throw new Error(`Fetch ${txId} failed: ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
}

function tags(node) {
  return Object.fromEntries(node.tags.map((tag) => [tag.name, tag.value]));
}

function cleanPath(path) {
  const normalized = path.replaceAll('\\', '/').split('/').filter(Boolean);
  if (normalized.some((part) => part === '..')) {
    throw new Error(`Refusing unsafe path: ${path}`);
  }
  return normalized.join('/');
}

async function readSnapshot(txId) {
  const raw = await bytes(txId);
  const body = raw[0] === 0x1f && raw[1] === 0x8b ? gunzipSync(raw) : raw;
  return JSON.parse(Buffer.from(body).toString('utf8'));
}

async function readBlobBundle(txId) {
  const raw = await bytes(txId);
  const body = raw[0] === 0x1f && raw[1] === 0x8b ? gunzipSync(raw) : raw;
  const text = Buffer.from(body).toString('utf8');
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`Blob bundle ${txId} is not JSON. Starts with: ${text.slice(0, 80)}`);
  }
}

function collectTree(snapshot) {
  const entriesByTree = new Map();
  if (snapshot.commit?.tree && snapshot.tree) {
    entriesByTree.set(snapshot.commit.tree, snapshot.tree);
  }
  for (const [sha, entries] of Object.entries(snapshot.subtrees || {})) {
    entriesByTree.set(sha, entries);
  }

  const files = [];
  function walk(treeSha, prefix = '') {
    const entries = entriesByTree.get(treeSha) || [];
    for (const entry of entries) {
      const path = prefix ? `${prefix}/${entry.name}` : entry.name;
      const mode = String(entry.mode || '');
      if (mode === '40000' || mode === '040000') {
        walk(entry.sha, path);
      } else {
        files.push({ ...entry, path: cleanPath(path) });
      }
    }
  }

  walk(snapshot.commit.tree);
  return files;
}

async function main() {
  const safeRepo = repo.replaceAll('"', '');
  const query = `{
    transactions(
      tags:[
        {name:"App-Name",values:["permagit"]},
        {name:"Type",values:["ref"]},
        {name:"Repo",values:["${safeRepo}"]}
      ],
      sort:HEIGHT_DESC,
      first:100
    ) {
      edges {
        node {
          id
          owner { address }
          tags { name value }
          block { timestamp height }
        }
      }
    }
  }`;

  const data = await gql(query);
  const refs = (data.transactions?.edges || []).map((edge) => {
    const tagMap = tags(edge.node);
    return {
      tx: edge.node.id,
      owner: edge.node.owner?.address || '',
      name: tagMap['Ref-Name'],
      target: tagMap['Ref-Target'],
      snapshotTx: tagMap['Snapshot-Tx'],
      packTx: tagMap['Pack-Tx'],
      block: edge.node.block,
    };
  }).filter((ref) => ref.name && ref.target);

  if (!refs.length) throw new Error(`No refs found for repo ${repo}`);

  const chosen = requestedRefOrCommit
    ? refs.find((ref) => ref.target === requestedRefOrCommit)
      || refs.find((ref) => ref.name === requestedRefOrCommit)
      || refs.find((ref) => ref.name?.endsWith(`/${requestedRefOrCommit}`))
    : refs.find((ref) => ref.name === 'refs/heads/main')
      || refs.find((ref) => ref.name?.endsWith('/main'))
      || refs.find((ref) => ref.name === 'refs/heads/master')
      || refs[0];

  if (!chosen) {
    const available = refs
      .slice(0, 20)
      .map((ref) => `${ref.name} ${ref.target}`)
      .join('\n');
    throw new Error(`No ref found for ${requestedRefOrCommit}. Available refs:\n${available}`);
  }

  if (!chosen.snapshotTx) {
    throw new Error(`Selected ref ${chosen.name} has no Snapshot-Tx; pack import is not implemented here.`);
  }

  const snapshot = await readSnapshot(chosen.snapshotTx);
  if (process.env.DEBUG_IMPORT) {
    await writeFile('_lapee_snapshot_debug.json', JSON.stringify(snapshot, null, 2));
  }
  const files = collectTree(snapshot);
  const blobBundles = new Map();

  await mkdir(outDir, { recursive: true });

  for (const file of files) {
    let content;
    if (file.sha === EMPTY_BLOB_SHA) {
      content = Buffer.alloc(0);
    } else if (snapshot.readme?.sha === file.sha && snapshot.readme?.content != null) {
      content = Buffer.from(snapshot.readme.content, 'utf8');
    } else if (snapshot.blobIndex?.[file.sha]) {
      const info = snapshot.blobIndex[file.sha];
      const bundleTx = typeof info === 'string' ? info : info.bundle || info.bundleTx || info.tx || info.txId;
      if (!bundleTx) {
        throw new Error(`Blob index entry for ${file.path} has no bundle tx: ${JSON.stringify(info)}`);
      }
      if (!blobBundles.has(bundleTx)) {
        blobBundles.set(bundleTx, await readBlobBundle(bundleTx));
      }
      const bundle = blobBundles.get(bundleTx);
      const blob = bundle.blobs?.[file.sha] || bundle[file.sha];
      if (!blob) throw new Error(`Blob ${file.sha} missing from bundle ${bundleTx}`);
      content = Buffer.from(blob.content || blob.data || blob, blob.encoding || 'base64');
    } else if (file.content != null) {
      content = Buffer.from(file.content, file.encoding || 'utf8');
    } else {
      console.warn(`Skipping ${file.path}: no blob content in snapshot`);
      continue;
    }

    const target = join(outDir, file.path);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, content);
  }

  await writeFile(join(outDir, '.permagit-import.json'), JSON.stringify({
    repo,
    ref: chosen.name,
    refTx: chosen.tx,
    commit: chosen.target,
    snapshotTx: chosen.snapshotTx,
    importedFiles: files.length,
  }, null, 2));

  console.log(`Imported ${files.length} files from ${repo} ${chosen.name} into ${outDir}`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
