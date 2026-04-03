import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const supportDir = path.dirname(fileURLToPath(import.meta.url));

export const typescriptRoot = path.resolve(supportDir, '..');
export const repoRoot = path.resolve(typescriptRoot, '../..');
export const generatedRoot = path.join(typescriptRoot, 'generated');
export const generatedPackageRoot = path.join(generatedRoot, 'arlen');
export const generatedManifestPath = path.join(generatedRoot, 'arlen.manifest.json');

function readTextFile(filePath: string): string {
  return fs.readFileSync(filePath, 'utf8');
}

export function readRepoText(relativePath: string): string {
  return readTextFile(path.join(repoRoot, relativePath));
}

export function readRepoJSON<T>(relativePath: string): T {
  return JSON.parse(readRepoText(relativePath)) as T;
}

export function readGeneratedText(relativePath: string): string {
  return readTextFile(path.join(generatedPackageRoot, relativePath));
}

export function readGeneratedJSON<T>(relativePath: string): T {
  return JSON.parse(readGeneratedText(relativePath)) as T;
}

export function readGeneratedManifest<T>(): T {
  return JSON.parse(readTextFile(generatedManifestPath)) as T;
}

export function readGeneratedManifestText(): string {
  return readTextFile(generatedManifestPath);
}

export function sha256(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

export function lineCount(value: string): number {
  if (value.length === 0) {
    return 0;
  }
  return value.split('\n').length;
}

export function createJSONResponse(body: unknown, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers ?? {});
  if (!headers.has('content-type')) {
    headers.set('content-type', 'application/json; charset=utf-8');
  }
  return new Response(JSON.stringify(body), {
    ...init,
    headers,
  });
}
