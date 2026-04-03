import assert from 'node:assert/strict';
import test from 'node:test';

import {
  lineCount,
  readGeneratedManifestText,
  readGeneratedText,
  readRepoJSON,
  sha256,
} from '../shared/phase28_support.ts';

interface SnapshotFileDescriptor {
  readonly bytes: number;
  readonly lines: number;
  readonly sha256: string;
}

interface SnapshotFixture {
  readonly format: string;
  readonly files: Record<string, SnapshotFileDescriptor>;
  readonly manifest: Record<string, unknown>;
  readonly manifestSha256: string;
}

test('generated package snapshot and manifest remain stable', () => {
  const fixture = readRepoJSON<SnapshotFixture>('tests/fixtures/phase28/typescript_snapshot.json');
  assert.equal(fixture.format, 'phase28-typescript-snapshot-v1');

  const manifestText = readGeneratedManifestText();
  assert.equal(sha256(manifestText), fixture.manifestSha256);
  assert.deepEqual(JSON.parse(manifestText), fixture.manifest);

  for (const [relativePath, expected] of Object.entries(fixture.files)) {
    const text = readGeneratedText(relativePath);
    assert.deepEqual(
      {
        bytes: Buffer.byteLength(text, 'utf8'),
        lines: lineCount(text),
        sha256: sha256(text),
      },
      expected,
      relativePath
    );
  }
});
