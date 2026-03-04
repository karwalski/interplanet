/**
 * Minimal ambient type declarations for Node.js built-ins.
 * Used by security.ts, merkle.ts, keydist.ts so they compile without @types/node.
 * Only the subset needed here is declared.
 */

// Declare require() globally (normally provided by @types/node)
declare function require(id: string): unknown;

// Minimal Buffer type (Node.js runtime shape — subset used in security.ts, merkle.ts, keydist.ts)
declare interface Buffer {
  readonly length: number;
  slice(start?: number, end?: number): Buffer;
  toString(encoding: string): string;
  copy(target: Buffer, targetStart?: number): void;
  [index: number]: number;
}

declare var Buffer: {
  from(data: string, encoding: string): Buffer;
  from(data: number[]): Buffer;
  alloc(size: number): Buffer;
  concat(buffers: Buffer[]): Buffer;
};

// Ambient module: node:crypto (subset used in security.ts, merkle.ts, keydist.ts)
declare module 'node:crypto' {
  interface NodeKeyObject {
    export(options: { type: 'spki';  format: 'der' }): Buffer;
    export(options: { type: 'pkcs8'; format: 'der' }): Buffer;
  }

  interface NodePrivateKeyInput {
    key: Buffer;
    format: 'der';
    type: 'pkcs8';
  }

  interface NodePublicKeyInput {
    key: Buffer;
    format: 'der';
    type: 'spki';
  }

  interface NodeKeyPairSyncResult {
    privateKey: NodeKeyObject;
    publicKey:  NodeKeyObject;
  }

  interface NodeHash {
    update(data: Buffer | string): NodeHash;
    digest(): Buffer;
    digest(encoding: 'hex' | 'base64' | 'base64url'): string;
  }

  interface NodeHmac {
    update(data: Buffer | string): NodeHmac;
    digest(): Buffer;
    digest(encoding: 'base64url'): string;
  }

  function generateKeyPairSync(type: 'ed25519'): NodeKeyPairSyncResult;
  function createHash(algorithm: 'sha256'): NodeHash;
  function createHmac(algorithm: 'sha256', key: Buffer): NodeHmac;
  function randomBytes(size: number): Buffer;
  function timingSafeEqual(a: Buffer, b: Buffer): boolean;
  function createPrivateKey(input: NodePrivateKeyInput): NodeKeyObject;
  function createPublicKey(input: NodePublicKeyInput): NodeKeyObject;
  function sign(algorithm: null, data: Buffer, key: NodeKeyObject): Buffer;
  function verify(algorithm: null, data: Buffer, key: NodeKeyObject, signature: Buffer): boolean;
}

// Ambient module: node:buffer
declare module 'node:buffer' {
  var Buffer: {
    from(data: string, encoding: string): import('node:crypto').NodeHash extends never ? never : Buffer;
  };
}
